#!/usr/bin/env python3
"""Write campaigns/<id>/report.md from a campaign's verdicts and runs.

    report.py <id>

The facts only: what ran, the verdict per machine and scenario, the per-cycle numbers and
the per-phase means. agent-analyst and agent-writer add the explanation afterwards, in
campaigns/<id>/analysis.md, which this report links to when present.
"""
import glob, json, os, sys

LAB = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
CAMPAIGNS = os.path.join(LAB, "campaigns")


def ms(x):
    return f"{x:,.1f}" if isinstance(x, (int, float)) else "n/a"


def ratio(delta_pct, short=False):
    """A percent change as a symmetric speed ratio: -60% and +150% are both 2.5x, one each way.
    Percent is lopsided (faster is capped at -100%, slower is unbounded), so it makes two
    gaps of the same size look different."""
    r = 1 + delta_pct / 100
    if r <= 0:
        # -100%: rustock reports 0 ms for the phase (onBestBlockMs on the mined and
        # replay paths), so there is no ratio to give.
        return "rustock 0 ms" if short else "rustock reports 0 ms for it"
    if short:
        return f"{1 / r:.2f}x faster" if r < 1 else f"{r:.2f}x slower"
    return f"rustock {1 / r:.2f}x faster than RSKj" if r < 1 else f"rustock {r:.2f}x slower than RSKj"


def arm_table(raw):
    """Per live arm: what it mined, what k6 saw, whether the cross replay passed."""
    rows = []
    for p in sorted(glob.glob(os.path.join(raw, "c*-*", "consensus.json")),
                    key=lambda x: (int(os.path.basename(os.path.dirname(x))[1:].split("-")[0]), x)):
        k = json.load(open(p))
        name = os.path.basename(os.path.dirname(p))
        cycle, client = name[1:].split("-", 1)
        cross = k.get("cross_replay")
        cross_s = "ok" if k.get("checks", {}).get("cross_replay") else \
            ("not run" if cross == "not run" else f"FAILED at {cross.get('first_difference') or '?'}" if isinstance(cross, dict) else "n/a")
        pct = k.get("k6_success_pct")
        rows.append(f"| {cycle} | {client} | {k.get('expected', 'n/a')} | {k.get('qualifying_blocks', 'n/a')} | "
                    f"{k.get('tx_count', 'n/a')} | {(k.get('gas_used') or 0):,} | "
                    f"{pct if pct is None else f'{pct:.2f}%'} | {cross_s} | {'yes' if k.get('consensus_ok') else 'no'} |")
    if not rows:
        return []
    return ["| cycle | client | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |",
            "|---|---|---|---|---|---|---|---|---|"] + rows + [""]


def main(cid):
    d = os.path.join(CAMPAIGNS, cid)
    c = json.load(open(os.path.join(d, "campaign.json")))
    shas = c.get("shas", {})
    live = c.get("kind", "replay") == "live"
    L = [f"# Campaign {cid}: RSKj vs rustock" + (", live mining" if live else ""), ""]
    if c.get("note"):
        L += [c["note"], ""]
    L += [f"Status **{c['status']}**, queued {c.get('queued_at')}, finished {c.get('finished_at', 'n/a')}.", "",
          "| client | ref | commit |", "|---|---|---|",
          f"| RSKj | `{c['refs']['rskj']}` | `{shas.get('rskj', '?')[:12]}` |",
          f"| rustock | `{c['refs']['rustock']}` | `{shas.get('rustock', '?')[:12]}` |", ""]
    if c.get("error"):
        L += ["## Stopped", "", "```", c["error"][-3000:], "```", ""]
    cfg = c.get("settings", {}).get("config", {})
    dk = cfg.get("docker", {})
    lv = cfg.get("live", {})
    if live:
        L += [f"Each arm has one client mine its own blocks under the scenario's k6 load for {lv.get('arm_minutes')} "
              "minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with "
              "the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held "
              f"and at least {lv.get('min_qualifying_blocks')} blocks were at least 90% full after the first "
              f"{lv.get('min_block')} (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: "
              "the paired design absorbs that, the per-arm table below shows how alike the load was. "
              "Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: "
              "rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign "
              "test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path "
              "rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).", "",
              f"Docker: both containers limited to {lv.get('cpus')} CPUs and {lv.get('memory')} memory "
              f"({lv.get('mainnet_memory')} on the mainnet seed); RSKj with `{dk.get('jvm_heap')}`, timed mining "
              "at a 10 s median in both; k6 on the host.", ""]
    else:
        mainnet = any(cfg.get("scenarios", {}).get(s, {}).get("db") == "mainnet" for s in c["scenarios"])
        start = ("a hard-link clone of the mainnet seed (`docs/mainnet-db-plan.md`)" if mainnet
                 else "an empty database")
        L += [f"Each run replays the scenario's blocks into one client from {start} and counts "
              "only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of "
              "per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent "
              "(negative means rustock is faster). Across cycles: the exact sign test. "
              "`docs/timing-scope.md` says what `totalMs` and each phase cover in each client.", "",
              f"Docker: both containers limited to {dk.get('cpus')} CPUs and "
              f"{dk.get('mainnet_memory') if mainnet else dk.get('memory')} memory; "
              f"RSKj with `{dk.get('jvm_heap')}`. Boton: fwd slot runs RSKj on box A and rustock on box B, "
              "rev swaps them, and the cycle's figure is the mean of the two boxes.", ""]
    rows = []
    for where in c["where"]:
        for scen in c["scenarios"]:
            p = os.path.join(d, f"verdict-{where}-{scen}.json")
            if os.path.exists(p):
                v = json.load(open(p))
                a = v.get("absolute_ms", {})
                t = v.get("totalMs", {}).get("tmean")
                rows.append(f"| {scen} | {where} | {ms(a.get('rskj', {}).get('totalMs'))} | "
                            f"{ms(a.get('rustock', {}).get('totalMs'))} | "
                            f"{ratio(t['median_pct'], short=True) if t else 'n/a'} | {v['verdict']} |")
    if rows:
        L += ["## Summary", "", "Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.", "",
              "| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |",
              "|---|---|---|---|---|---|"] + rows + [""]
    for where in c["where"]:
        for scen in c["scenarios"]:
            p = os.path.join(d, f"verdict-{where}-{scen}.json")
            if not os.path.exists(p):
                continue
            v = json.load(open(p))
            L += [f"## {scen}, {where}", "", f"**{v['verdict']}**: {v['why']}.", ""]
            if live:
                L += arm_table(os.path.join(d, "raw", where, scen))
            t = v.get("totalMs", {})
            if t:
                L += ["| statistic | rustock vs RSKj | rustock faster | p | per cycle |", "|---|---|---|---|---|"]
                for stat, name in (("tmean", "trimmed mean"), ("mean", "mean"), ("median", "median")):
                    if stat in t:
                        x = t[stat]
                        L.append(f"| {name} | {ratio(x['median_pct'], short=True)} | {x['rustock_faster']}/{x['n']} | "
                                 f"{x['p']:.3g} | {', '.join(ratio(y, short=True) for y in x['deltas_pct'])} |")
                L.append("")
            a = v.get("absolute_ms", {})
            if a:
                phases = sorted(set(a.get("rskj", {})) | set(a.get("rustock", {})),
                                key=lambda m: (m != "totalMs", m))
                L += ["Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not "
                      "log shows n/a; same-named phases are compared in the last column):", "",
                      "| phase | RSKj | rustock | rustock vs RSKj (paired median) |", "|---|---|---|---|"]
                for m in phases:
                    ph = v.get("phases", {}).get(m)
                    delta = f"{ratio(ph['median_pct'], short=True)} ({ph['rustock_faster']}/{ph['n']})" if ph else ""
                    if m == "totalMs" and "tmean" in t:
                        delta = ratio(t['tmean']['median_pct'], short=True)
                    L.append(f"| {m} | {ms(a.get('rskj', {}).get(m))} | {ms(a.get('rustock', {}).get(m))} | {delta} |")
                L.append("")
    if os.path.exists(os.path.join(d, "analysis.md")):
        L += ["## Analysis", "", "See [analysis.md](analysis.md).", ""]
    tmp = os.path.join(d, ".report.md")
    open(tmp, "w").write("\n".join(L))
    os.replace(tmp, os.path.join(d, "report.md"))
    print(os.path.join(d, "report.md"))


if __name__ == "__main__":
    main(sys.argv[1])
