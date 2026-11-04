#!/usr/bin/env python3
"""rsk-clients-lab driver: queue a campaign, run it, read its status.

    lab.py queue [--kind replay|live] [--where docker,boton] [--scenarios mainnet-sim,ecdsa]
                 [--cycles 6] [--rskj REF] [--rustock REF] [--note TEXT]   -> prints the campaign id
    lab.py run <id>          run one campaign in the foreground (start.sh runs it detached)
    lab.py next              run the oldest queued campaign, if any
    lab.py status [<id>]     one line per campaign, or one campaign's progress

A campaign resolves both client refs to commits once, at its start, so every cycle measures
the same two builds. Per scenario and machine it runs cycles until the verdict is decided or
max_cycles is reached (bin/stats.py). Every run is checked against the reference hashes; a
run that fails the check stops the campaign as a consensus finding, since timing a client
that computed something else means nothing.

A live campaign (--kind live) replaces the replay with bin/live-arm.sh: each client mines
its own blocks under k6 load for live.arm_minutes, the cycle then replays each arm's blocks
into the other client (the cross replay, in Docker on this Mac) and bin/check-live-arm.sh
decides whether the arm counts. The cycle loop, the lock handling and the verdict are the
same. On Boton (--where boton) a cycle is two slots of bin/boton-live-slot.sh: both boxes
mine at once, one client each, then swapped. On the mainnet seed the boxes hold one client's
seed at a time, so the campaign is sequential: every RSKj cycle, the seed swap
(bin/boton-seed.sh), every rustock cycle (docs/mainnet-db-plan.md).
"""
import argparse, datetime as dt, glob, json, os, subprocess, sys, time

LAB = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BIN = os.path.join(LAB, "bin")
STATE = os.path.join(LAB, "state")
CAMPAIGNS = os.path.join(LAB, "campaigns")
QUEUE = os.path.join(STATE, "queue")
CFG = json.load(open(os.path.join(LAB, "config.json")))
sys.path.insert(0, BIN)
import stats  # noqa: E402


def now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(msg, c=None):
    line = f"[{now()}] {msg}"
    print(line, flush=True)
    if c:
        with open(os.path.join(c["dir"], "campaign.log"), "a") as f:
            f.write(line + "\n")


def sh(args, env=None, check=True):
    e = dict(os.environ, **(env or {}))
    r = subprocess.run(args, capture_output=True, text=True, env=e)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed ({r.returncode}):\n{r.stderr[-3000:]}{r.stdout[-2000:]}")
    return r


def save(c):
    tmp = os.path.join(c["dir"], ".campaign.json")
    json.dump(c, open(tmp, "w"), indent=1)
    os.replace(tmp, os.path.join(c["dir"], "campaign.json"))


def load(cid):
    return json.load(open(os.path.join(CAMPAIGNS, cid, "campaign.json")))


def queue(a):
    os.makedirs(QUEUE, exist_ok=True)
    day = dt.date.today().isoformat()
    n = 1 + len(glob.glob(os.path.join(CAMPAIGNS, f"{day}-c*")))
    cid = f"{day}-c{n}"
    d = os.path.join(CAMPAIGNS, cid)
    os.makedirs(d)
    c = {"id": cid, "dir": d, "status": "queued", "queued_at": now(), "queued_epoch": int(time.time()),
         "kind": a.kind, "where": a.where.split(","), "scenarios": a.scenarios.split(","),
         "clients": a.clients.split(","),
         "cycles": a.cycles or CFG["campaign"]["cycles"], "max_cycles": CFG["campaign"]["max_cycles"],
         "refs": {"rskj": a.rskj or json.load(open(os.path.join(LAB, "clients/rskj.json")))["ref"],
                  "rustock": a.rustock or json.load(open(os.path.join(LAB, "clients/rustock.json")))["ref"]},
         "note": a.note or "", "results": {}}
    for s in c["scenarios"]:
        if s not in CFG["scenarios"]:
            sys.exit(f"unknown scenario {s}")
        if a.kind == "live" and CFG["scenarios"][s].get("k6_option") is None:
            sys.exit(f"scenario {s} has no k6_option; a live campaign needs one")
    save(c)
    open(os.path.join(QUEUE, cid), "w").close()
    print(cid)


def resolve(c):
    """Pin both clients to commits and build what the campaign's machines need."""
    # A campaign pins its commits once, at its first start: a rerun after an interruption
    # measures the same builds as the cycles already on disk, even if a branch moved since.
    shas = dict(c.get("shas") or {})
    for name, ref in c["refs"].items():
        if shas.get(name):
            continue
        repo = os.path.join(LAB, "clients", name)
        sh(["git", "-C", repo, "fetch", "-q", "--all"], check=False)
        shas[name] = sh(["git", "-C", repo, "rev-parse", "--verify", f"{ref}^{{commit}}"]).stdout.strip()
    c["shas"] = shas
    c["builds"] = {"rskj": sh([os.path.join(BIN, "build-client.sh"), "rskj", shas["rskj"]]).stdout.strip().splitlines()[-1]}
    # Release and Docker builds of rustock are heavy: run them in the shared Docker slot.
    # A live campaign cross-replays every arm in Docker here, wherever the arm ran.
    if ("docker" in c["where"] or c.get("kind", "replay") == "live") and "rustock" in c.get("clients", ["rskj", "rustock"]):
        sh([os.path.join(BIN, "with-lock.sh"), os.path.join(BIN, "build-client.sh"), "rustock", shas["rustock"], "linux-arm64"])
        c["builds"]["rustock-docker"] = f"clientslab-rustock:{shas['rustock'][:12]}-linux-arm64"
    if "boton" in c["where"]:
        c["builds"]["rustock-boton"] = sh([os.path.join(BIN, "with-lock.sh"), os.path.join(BIN, "build-client.sh"),
                                           "rustock", shas["rustock"], "linux-amd64"]).stdout.strip().splitlines()[-1]
    c["settings"] = {"config": CFG, "rskj": json.load(open(os.path.join(LAB, "clients/rskj.json"))),
                     "rustock": json.load(open(os.path.join(LAB, "clients/rustock.json")))}
    save(c)
    log(f"rskj {shas['rskj'][:9]}, rustock {shas['rustock'][:9]}", c)


class ConsensusFailure(Exception):
    pass


def docker_run(c, client, scen, out):
    art = c["builds"]["rskj"] if client == "rskj" else c["builds"]["rustock-docker"]
    r = sh([os.path.join(BIN, "replay-docker.sh"), client, art, scen, out],
           env={"CLIENTSLAB_DOCKER_LOCK_HELD": "1"}, check=False)
    cons = json.load(open(os.path.join(out, "consensus.json"))) if os.path.exists(os.path.join(out, "consensus.json")) else {}
    if r.returncode != 0:
        raise ConsensusFailure(f"{client} {scen}: {cons or r.stderr[-1500:]}")
    log(f"docker {scen} {os.path.basename(out)}: {cons.get('records')} blocks in {cons.get('wall_s')} s", c)


def live_arm(c, client, scen, out):
    art = c["builds"]["rskj"] if client == "rskj" else c["builds"]["rustock-docker"]
    # The arm's own log goes beside its directory (live-arm.sh empties the directory first).
    with open(out + ".log", "w") as f:
        r = subprocess.run([os.path.join(BIN, "live-arm.sh"), client, art, scen, out], stdout=f, stderr=subprocess.STDOUT,
                           env=dict(os.environ, CLIENTSLAB_DOCKER_LOCK_HELD="1"))
    if r.returncode != 0:
        tail = open(out + ".log", errors="replace").read()[-2000:]
        raise RuntimeError(f"live arm {client} {scen} {os.path.basename(out)} failed:\n{tail}")
    arm = json.load(open(os.path.join(out, "arm.json")))
    log(f"live {scen} {os.path.basename(out)}: blocks {arm['start_height'] + 1}..{arm['end_height']} in {arm['wall_s']} s", c)


def cross_replay(c, client, scen, out):
    """The arm's blocks into the OTHER client, from the same starting database."""
    other = "rustock" if client == "rskj" else "rskj"
    art = c["builds"]["rskj"] if other == "rskj" else c["builds"]["rustock-docker"]
    arm = json.load(open(os.path.join(out, "arm.json")))
    if arm["blocks_exported"] < 1:
        return  # nothing to replay; check-live-arm.sh discards the arm
    sh([os.path.join(BIN, "replay-docker.sh"), other, art, scen, os.path.join(out, "cross"),
        "--blocks", os.path.join(out, "blocks.txt.gz"), "--hashes", os.path.join(out, "hashes.txt"),
        "--first", str(arm["start_height"] + 1), "--last", str(arm["end_height"])],
       env={"CLIENTSLAB_DOCKER_LOCK_HELD": "1"}, check=False)


def check_live(c, client, scen, out):
    r = sh([os.path.join(BIN, "check-live-arm.sh"), client, scen, out], check=False)
    p = os.path.join(out, "consensus.json")
    cons = json.load(open(p)) if os.path.exists(p) else {}
    if r.returncode == 3:
        raise ConsensusFailure(f"{client} {scen} {os.path.basename(out)} cross replay: {cons.get('cross_replay')}")
    if r.returncode != 0:
        raise ArmDiscarded(f"{client} {scen} {os.path.basename(out)}: {cons or r.stderr[-1500:]}")
    log(f"live {scen} {os.path.basename(out)}: {cons.get('expected')} blocks mined, {cons.get('qualifying_blocks')} qualifying, "
        f"k6 {cons.get('k6_success_pct')}%, cross replay ok", c)


def run_docker(c, scen):
    """The Docker cycles of one scenario, replay or live (campaign.json kind)."""
    d = os.path.join(c["dir"], "raw", "docker", scen)
    os.makedirs(d, exist_ok=True)
    k = 0
    while True:
        k += 1
        if k > c["max_cycles"]:
            break
        # A sequential campaign (docs/mainnet-db-plan.md) runs one client's cycles now and the
        # other's later with `run --clients`; a cycle is complete when every listed client is.
        clients = tuple(c.get("clients", ["rskj", "rustock"]))
        done = all(os.path.exists(os.path.join(d, f"c{k}-{x}", "consensus.json")) and stats.per_block(os.path.join(d, f"c{k}-{x}"))
                   for x in clients)
        if not done:  # else: done in an earlier attempt, but still judged below
            order = clients if k % 2 or len(clients) == 1 else tuple(reversed(clients))
            # One cycle holds the Docker slot as a long holder: another lab's short jobs
            # may run between cycles, never between the two runs of one cycle.
            env = {"CLIENTSLAB_PRIORITY": str(c["queued_epoch"])}
            cmd = f'. "{BIN}/lib.sh"; lock_acquire docker "long:$CLIENTSLAB_PRIORITY"; trap "lock_release docker" EXIT; ' \
                  f'"{sys.executable}" "{BIN}/lab.py" _cycle "{c["id"]}" "{scen}" {k} {" ".join(order)}'
            r = subprocess.run(["bash", "-c", cmd], env=dict(os.environ, **env))
            if r.returncode == 3:
                raise ConsensusFailure(open(os.path.join(d, "consensus-failure.txt")).read())
            if r.returncode == 4:
                raise RuntimeError("live arm discarded, rerun the campaign to repeat the cycle: "
                                   + open(os.path.join(d, "arm-discarded.txt")).read())
            if r.returncode != 0:
                raise RuntimeError(f"docker cycle {k} of {scen} failed (exit {r.returncode})")
        if k >= c["cycles"]:
            v = stats.judge("docker", d, scen)
            log(f"docker {scen} after {k} cycles: {v['verdict']} ({v['why']})", c)
            if v["verdict"] != "extend":
                break
            if len(clients) == 1 and k >= c["cycles"]:
                break  # one client alone cannot be judged; the other half decides later
    v = stats.judge("docker", d, scen)
    json.dump(v, open(os.path.join(c["dir"], f"verdict-docker-{scen}.json"), "w"), indent=1)
    return v


run_live = run_docker  # the same loop; the cycle below is what differs


class ArmDiscarded(Exception):
    pass


def cycle(cid, scen, k, order):
    """One Docker cycle, called under the lock by run_docker. A replay cycle is one run per
    client; a live cycle is one arm per client, then each arm's cross replay into the other
    client, then the checks (an arm that measured nothing is discarded, exit 4)."""
    c = load(cid)
    d = os.path.join(c["dir"], "raw", "docker", scen)
    try:
        if c.get("kind", "replay") == "live":
            for client in order:
                live_arm(c, client, scen, os.path.join(d, f"c{k}-{client}"))
            for client in order:
                cross_replay(c, client, scen, os.path.join(d, f"c{k}-{client}"))
            for client in order:
                check_live(c, client, scen, os.path.join(d, f"c{k}-{client}"))
        else:
            for client in order:
                docker_run(c, client, scen, os.path.join(d, f"c{k}-{client}"))
    except ConsensusFailure as e:
        open(os.path.join(d, "consensus-failure.txt"), "w").write(str(e))
        sys.exit(3)
    except ArmDiscarded as e:
        open(os.path.join(d, "arm-discarded.txt"), "w").write(str(e))
        sys.exit(4)


# The Boton live layout, per cycle k: c<k>-fwd/{A,B} and c<k>-rev/{A,B}; bin/stats.py
# boton_cycles pairs box A's rskj fwd with its rustock rev and box B's rskj rev with its
# rustock fwd. A unit is what one bin/boton-live-slot.sh call runs, as (slot, box, client)
# arms: on an empty database the two counterbalanced slots; on the mainnet seed one client on
# both boxes, since the boxes hold one client's seed at a time (docs/mainnet-db-plan.md).
BOTON_UNITS = {
    "fwd": (("fwd", "A", "rskj"), ("fwd", "B", "rustock")),
    "rev": (("rev", "A", "rustock"), ("rev", "B", "rskj")),
    "rskj": (("fwd", "A", "rskj"), ("rev", "B", "rskj")),
    "rustock": (("rev", "A", "rustock"), ("fwd", "B", "rustock")),
}


def boton_sequential(scen):
    return CFG["scenarios"][scen].get("db", "empty") != "empty"


def boton_arm_dir(d, k, slot, box):
    return os.path.join(d, f"c{k}-{slot}", box)


def boton_seed(c, client):
    """Both boxes get the client's seed (bin/boton-seed.sh, a no-op on a box that has it),
    in parallel: most of a day when a seed has to be uploaded."""
    d = os.path.join(c["dir"], "raw", "boton")
    log(f"boton: staging the {client} seed on both boxes (bin/boton-seed.sh, raw/boton/seed-{client}-<box>.log)", c)
    t0 = time.time()
    procs = {}
    for box in CFG["boton"]["boxes"]:
        f = open(os.path.join(d, f"seed-{client}-{box}.log"), "a")
        procs[box] = subprocess.Popen([os.path.join(BIN, "boton-seed.sh"), box, client], stdout=f, stderr=subprocess.STDOUT)
    failed = [box for box, p in procs.items() if p.wait() != 0]
    if failed:
        raise RuntimeError(f"staging the {client} seed failed on box {' and '.join(failed)}; see raw/boton/seed-{client}-<box>.log")
    log(f"boton: both boxes hold the {client} seed ({int((time.time() - t0) / 60)} min)", c)


def boton_unit_done(d, k, unit):
    return all(stats.per_block(boton_arm_dir(d, k, slot, box)) for slot, box, _ in BOTON_UNITS[unit])


def boton_unit(c, scen, d, k, unit):
    """One unit of cycle k, unless its arms already count: the slot on the boxes (which holds
    the box locks), then the arms' cross replays and checks in Docker here. An arm that
    measured nothing repeats the unit, up to three attempts; a cross replay that fails stops
    the campaign."""
    if boton_unit_done(d, k, unit):
        return
    arms = BOTON_UNITS[unit]
    by_box = {box: (slot, client) for slot, box, client in arms}
    args = []
    for box in ("A", "B"):
        slot, client = by_box[box]
        args += [boton_arm_dir(d, k, slot, box), client]
    logf = os.path.join(d, f"c{k}-{unit}.log")
    for attempt in range(1, 4):
        for slot, box, _ in arms:
            sh(["rm", "-rf", boton_arm_dir(d, k, slot, box)])
        with open(logf, "a") as f:
            r = subprocess.run([os.path.join(BIN, "boton-live-slot.sh"), c["id"], scen] + args,
                               stdout=f, stderr=subprocess.STDOUT,
                               env=dict(os.environ, CLIENTSLAB_PRIORITY=str(c["queued_epoch"])))
        if r.returncode != 0:
            tail = sh(["tail", "-n", "5", logf], check=False).stdout
            raise RuntimeError(f"boton live c{k}-{unit} of {scen} failed (exit {r.returncode}):\n{tail}")
        cmd = f'. "{BIN}/lib.sh"; lock_acquire docker "long:$CLIENTSLAB_PRIORITY"; trap "lock_release docker" EXIT; ' \
              f'"{sys.executable}" "{BIN}/lab.py" _boton_check "{c["id"]}" "{scen}" {k} {unit}'
        r = subprocess.run(["bash", "-c", cmd], env=dict(os.environ, CLIENTSLAB_PRIORITY=str(c["queued_epoch"])))
        if r.returncode == 3:
            raise ConsensusFailure(open(os.path.join(d, "consensus-failure.txt")).read())
        if r.returncode == 4:
            log(f"boton live c{k}-{unit} of {scen}, attempt {attempt}: arm discarded, repeating the unit: "
                + open(os.path.join(d, "arm-discarded.txt")).read().strip(), c)
            continue
        if r.returncode != 0:
            raise RuntimeError(f"boton live checks of c{k}-{unit} of {scen} failed (exit {r.returncode})")
        return
    raise RuntimeError(f"boton live c{k}-{unit} of {scen} discarded three times; see arm-discarded.txt")


def run_boton_live(c, scen):
    """The Boton cycles of one live scenario. Empty database: per cycle the fwd and the rev
    unit, judged after `cycles` and extended while undecided. Mainnet seed: sequential, every
    cycle of one client (both boxes at once), the seed swap, every cycle of the other, then
    the verdict; never extended, since more cycles would need another seed swap."""
    d = os.path.join(c["dir"], "raw", "boton", scen)
    os.makedirs(d, exist_ok=True)
    if boton_sequential(scen):
        for client in c.get("clients", ["rskj", "rustock"]):
            if all(boton_unit_done(d, k, client) for k in range(1, c["cycles"] + 1)):
                continue  # a rerun: this half is done, and its seed may be gone from the boxes
            boton_seed(c, client)
            for k in range(1, c["cycles"] + 1):
                boton_unit(c, scen, d, k, client)
        v = stats.judge("boton", d, scen)
        log(f"boton {scen} after {c['cycles']} sequential cycles: {v['verdict']} ({v['why']})"
            + ("; not extended: more cycles would need another seed swap" if v["verdict"] == "extend" else ""), c)
        return v
    k = 0
    while True:
        k += 1
        if k > c["max_cycles"]:
            break
        for unit in ("fwd", "rev"):
            boton_unit(c, scen, d, k, unit)
        if k >= c["cycles"]:
            v = stats.judge("boton", d, scen)
            log(f"boton {scen} after {k} cycles: {v['verdict']} ({v['why']})", c)
            if v["verdict"] != "extend":
                break
    return stats.judge("boton", d, scen)


def boton_check(cid, scen, k, unit):
    """The arms of one Boton live unit: cross replay in Docker, then the checks. Called under
    the Docker lock by boton_unit; exit 3 on a consensus failure, 4 when an arm measured
    nothing."""
    c = load(cid)
    d = os.path.join(c["dir"], "raw", "boton", scen)
    arms = BOTON_UNITS[unit]
    try:
        for slot, box, client in arms:
            cross_replay(c, client, scen, boton_arm_dir(d, k, slot, box))
        for slot, box, client in arms:
            check_live(c, client, scen, boton_arm_dir(d, k, slot, box))
    except ConsensusFailure as e:
        open(os.path.join(d, "consensus-failure.txt"), "w").write(str(e))
        sys.exit(3)
    except ArmDiscarded as e:
        open(os.path.join(d, "arm-discarded.txt"), "w").write(str(e))
        sys.exit(4)


def run(cid):
    c = load(cid)
    c["status"] = "running"
    c["started_at"] = now()
    c.pop("error", None)
    c.pop("finished_at", None)
    save(c)
    q = os.path.join(QUEUE, cid)
    try:
        resolve(c)
        for where in c["where"]:
            for scen in c["scenarios"]:
                if where == "docker":
                    v = (run_live if c.get("kind", "replay") == "live" else run_docker)(c, scen)
                elif c.get("kind", "replay") == "live":
                    v = run_boton_live(c, scen)
                    json.dump(v, open(os.path.join(c["dir"], f"verdict-boton-{scen}.json"), "w"), indent=1)
                else:
                    v = sh([os.path.join(BIN, "boton-campaign.sh"), cid, scen], check=True) and \
                        stats.judge("boton", os.path.join(c["dir"], "raw", "boton", scen), scen)
                    json.dump(v, open(os.path.join(c["dir"], f"verdict-boton-{scen}.json"), "w"), indent=1)
                c["results"][f"{where}/{scen}"] = {"verdict": v["verdict"], "why": v["why"]}
                save(c)
        c["status"] = "done"
        c.pop("error", None)
    except ConsensusFailure as e:
        c["status"] = "consensus-failure"; c["error"] = str(e)
        log(f"consensus failure: {e}", c)
    except Exception as e:  # noqa: BLE001 - recorded for agent-diagnose and the user
        c["status"] = "failed"; c["error"] = str(e)
        log(f"failed: {e}", c)
    c["finished_at"] = now(); save(c)
    if os.path.exists(q):
        os.remove(q)
    sh([sys.executable, os.path.join(BIN, "report.py"), cid], check=False)


def status(cid=None):
    if cid:
        c = load(cid)
        print(json.dumps({k: c.get(k) for k in ("id", "status", "kind", "where", "scenarios", "shas", "results", "error")}, indent=1))
        return
    for p in sorted(glob.glob(os.path.join(CAMPAIGNS, "*", "campaign.json"))):
        c = json.load(open(p))
        res = "; ".join(f"{k}: {v['verdict']}" for k, v in c.get("results", {}).items())
        print(f"{c['id']:16s} {c['status']:18s} {c.get('kind', 'replay'):7s} {','.join(c['where']):13s} {','.join(c['scenarios']):18s} {res}")


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    q = sp.add_parser("queue")
    q.add_argument("--kind", choices=("replay", "live"), default="replay")
    q.add_argument("--where", default="docker")
    q.add_argument("--scenarios", default="mainnet-sim,ecdsa")
    q.add_argument("--cycles", type=int)
    q.add_argument("--rskj"); q.add_argument("--rustock"); q.add_argument("--note")
    q.add_argument("--clients", default="rskj,rustock", help="run only these clients' cycles now (sequential campaigns)")
    r = sp.add_parser("run"); r.add_argument("id"); r.add_argument("--clients", help="the clients to run in this pass")
    sp.add_parser("next")
    sp.add_parser("status").add_argument("id", nargs="?")
    cy = sp.add_parser("_cycle")
    cy.add_argument("id"); cy.add_argument("scen"); cy.add_argument("k", type=int); cy.add_argument("order", nargs="+")
    bc = sp.add_parser("_boton_check")
    bc.add_argument("id"); bc.add_argument("scen"); bc.add_argument("k", type=int); bc.add_argument("unit", choices=tuple(BOTON_UNITS))
    a = ap.parse_args()
    if a.cmd == "queue":
        queue(a)
    elif a.cmd == "run":
        if a.clients:
            c = load(a.id); c["clients"] = a.clients.split(","); save(c)
        run(a.id)
    elif a.cmd == "next":
        ids = sorted(os.listdir(QUEUE)) if os.path.isdir(QUEUE) else []
        if ids:
            run(ids[0])
    elif a.cmd == "status":
        status(a.id)
    elif a.cmd == "_cycle":
        cycle(a.id, a.scen, a.k, a.order)
    elif a.cmd == "_boton_check":
        boton_check(a.id, a.scen, a.k, a.unit)


if __name__ == "__main__":
    main()
