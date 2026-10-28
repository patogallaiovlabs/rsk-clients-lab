#!/usr/bin/env python3
"""Verdict for one scenario of a campaign: is rustock faster than RSKj, slower, or neither?

    stats.py docker <scenario-dir>   # <dir>/c<k>-rskj, <dir>/c<k>-rustock (bin/replay-docker.sh output)
    stats.py boton  <scenario-dir>   # <dir>/c<k>-fwd/{A,B}, <dir>/c<k>-rev/{A,B}

Prints one JSON object. The rule is the one RSKj's own A/B benchmarks use, read as a
two-sided comparison. The cycle is the unit of replication: blocks within one run share a
process, page cache and database, so pooling blocks gives a meaninglessly tight interval.
Each cycle gives one paired difference, rustock vs RSKj, in percent of the per-run 10%
trimmed mean of per-block totalMs over the qualifying blocks; the exact two-sided sign test
asks how often the direction repeats.

  rustock faster : p < alpha, median difference <= -min_difference_pct, majority faster
  rustock slower : p < alpha, median difference >= +min_difference_pct, majority slower
  extend         : not decided, cycles < max_cycles, |median| >= min_difference_pct and at
                   most one cycle disagrees with it
  no difference  : otherwise

On Boton each cycle is two slots: fwd runs RSKj on box A and rustock on box B, rev swaps
them, so the box term cancels in the mean of the two per-box differences.

The plain mean and the median of the same cycles are reported beside the trimmed mean, and
every phase both clients log under the same name gets the same paired treatment.
"""
import glob, json, os, statistics as st, sys

LAB = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, os.path.join(LAB, "bin"))
from paired_stats import sign_test  # noqa: E402

CFG = json.load(open(os.path.join(LAB, "config.json")))
STAT_KEY = {"tmean": "tmean10", "mean": "mean", "median": "p50"}


def pct(ref, x):
    return 100.0 * (x - ref) / ref if ref else None


def per_block(run_dir):
    """A run's per-block statistics, or None if the run does not count."""
    try:
        if not json.load(open(os.path.join(run_dir, "consensus.json")))["consensus_ok"]:
            return None
        return json.load(open(os.path.join(run_dir, "summary.json")))["per_block"]
    except (OSError, KeyError, ValueError):
        return None


def docker_cycles(d):
    out = []
    for r in sorted(glob.glob(os.path.join(d, "c*-rskj"))):
        a, b = per_block(r), per_block(r[:-len("rskj")] + "rustock")
        if a and b:
            out.append([(a, b)])
    return out


def boton_cycles(d):
    """Per cycle, the two (rskj, rustock) pairs: box A and box B."""
    out = []
    for fwd in sorted(glob.glob(os.path.join(d, "c*-fwd"))):
        rev = fwd[:-len("fwd")] + "rev"
        fa, fb, ra, rb = (per_block(os.path.join(s, x)) for s in (fwd, rev) for x in ("A", "B"))
        if all((fa, fb, ra, rb)):
            out.append([(fa, ra), (rb, fb)])  # box A: rskj fwd, rustock rev; box B: rskj rev, rustock fwd
    return out


def deltas(cycles, metric, stat):
    k = STAT_KEY[stat]
    ds = []
    for pairs in cycles:
        try:
            vs = [pct(a[metric][k], b[metric][k]) for a, b in pairs]
        except (KeyError, TypeError):
            continue
        if all(v is not None for v in vs):
            ds.append(sum(vs) / len(vs))
    return ds


def decide(ds, min_pct, max_cycles, alpha):
    if not ds:
        return "no data", "no complete cycles"
    k, n, p = sign_test(ds)  # k = cycles where rustock was faster
    med = st.median(ds)
    why = f"rustock faster in {k}/{n} cycles, median {med:+.2f}%, sign-test p={p}"
    if p is not None and p < alpha and med <= -min_pct and k > n - k:
        return "rustock faster", why
    if p is not None and p < alpha and med >= min_pct and n - k > k:
        return "rustock slower", why
    disagree = (n - k) if med < 0 else k
    if len(ds) < max_cycles and abs(med) >= min_pct and disagree <= 1:
        return "extend", why
    return "no difference", why


def judge(where, d, scenario):
    cycles = (docker_cycles if where == "docker" else boton_cycles)(d)
    sc = CFG["scenarios"][scenario]
    c = CFG["campaign"]
    ds = deltas(cycles, "totalMs", "tmean")
    verdict, why = decide(ds, sc["min_difference_pct"], c["max_cycles"], c["alpha"])
    out = {"where": where, "scenario": scenario, "cycles": len(cycles), "verdict": verdict, "why": why,
           "totalMs": {}, "phases": {}, "absolute_ms": {}}
    for stat in ("tmean", "mean", "median"):
        x = deltas(cycles, "totalMs", stat)
        if x:
            k, n, p = sign_test(x)
            out["totalMs"][stat] = {"median_pct": round(st.median(x), 2), "rustock_faster": k, "n": n, "p": p,
                                    "deltas_pct": [round(v, 2) for v in x]}
    # Per client, the mean over runs of each phase's trimmed mean, for every phase it logs.
    for i, name in enumerate(("rskj", "rustock")):
        runs = [pair[i] for pairs in cycles for pair in pairs]
        phases = sorted({m for r in runs for m in r})
        out["absolute_ms"][name] = {m: round(st.mean([r[m]["tmean10"] for r in runs if m in r]), 3) for m in phases}
    shared = set(out["absolute_ms"].get("rskj", {})) & set(out["absolute_ms"].get("rustock", {}))
    for m in sorted(shared - {"totalMs"}):
        x = deltas(cycles, m, "tmean")
        if x:
            k, n, p = sign_test(x)
            out["phases"][m] = {"median_pct": round(st.median(x), 2), "rustock_faster": k, "n": n, "p": p}
    return out


if __name__ == "__main__":
    where, d = sys.argv[1], sys.argv[2]
    scenario = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(os.path.normpath(d))
    print(json.dumps(judge(where, d, scenario), indent=1))
