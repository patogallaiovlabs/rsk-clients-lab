#!/usr/bin/env python3
"""Pool repeated A/B cycles into one paired statistic per scenario.

    scripts/paired_stats.py local            # results/local-ab/seq*-<scenario>-{baseline,tip}
    scripts/paired_stats.py boton            # results/boton/bseq*-<scenario>-{fwd,rev}
    scripts/paired_stats.py local calldata   # one scenario

WHY THIS EXISTS. A single A/B cycle cannot separate a build effect from run-to-run
noise: with the same build on both sides, local cycles varied 12-14% on totalMs and
co-located Boton boxes ~8%. One run landing at -20% therefore proves nothing. What
carries an argument is REPEATED cycles agreeing in direction.

The cycle is the unit of replication, not the block. Blocks within one arm are not
independent -- they share a JVM, a page cache and a database that grew over the run --
so pooling thousands of blocks yields a tiny, meaningless confidence interval. This
script pairs each cycle's two arms, takes one delta per cycle, and asks how often the
direction repeats: an exact two-sided sign test, which assumes nothing about the
distribution of the noise.

The sign test is deliberately weak. It cannot reach p<0.05 with fewer than 6 cycles
even if every one agrees (2/2^6 = 0.031), so with 5 cycles the honest answer is
"consistent direction, not yet significant". That is the point: it will not manufacture
significance the data does not contain.

Boton cycles are read through crossover_estimate.py rather than re-derived here, so the
box-role naming trap is handled in exactly one place.
"""
import sys, os, re, glob, json, subprocess, statistics as st
from math import comb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIM = 25_000_000
METRICS = ["totalMs", "preambleMs", "executeMs", "saveReceiptsMs", "txExecutionMs"]

NUM = r"(\d+(?:\.\d+)?)"
RXC = re.compile(
    rf"block connect breakdown.*?totalMs={NUM}.*?executeMs={NUM}.*?"
    rf"saveReceiptsMs={NUM}.*?gasUsed={NUM}")
RXE = re.compile(rf"block execute breakdown.*?totalMs={NUM} txExecutionMs={NUM}.*?gasUsed={NUM}")


def sign_test(deltas, tol=1e-9):
    """Exact two-sided sign test. Ties (zero delta) are dropped, the standard
    conservative handling -- a tie is evidence for neither direction."""
    nz = [d for d in deltas if abs(d) > tol]
    n = len(nz)
    if n == 0:
        return 0, 0, None
    k = sum(1 for d in nz if d < 0)          # count of "tip faster"
    hits = max(k, n - k)
    p = min(1.0, 2.0 * sum(comb(n, i) for i in range(hits, n + 1)) / 2 ** n)
    return k, n, p


def local_arm(d, thr=0.9):
    out = {m: [] for m in METRICS}
    f = os.path.join(d, "block-breakdown.log")
    if not os.path.exists(f):
        return None
    for ln in open(f, errors="ignore"):
        m = RXC.search(ln)
        if m:
            t, e, s, g = (float(x) for x in m.groups())
            if g >= thr * LIM:
                out["totalMs"].append(t); out["executeMs"].append(e)
                out["saveReceiptsMs"].append(s)
            continue
        m = RXE.search(ln)
        if m:
            _, x, g = (float(v) for v in m.groups())
            if g >= thr * LIM:
                out["txExecutionMs"].append(x)
    return out if out["totalMs"] else None


def collect_local(scenario):
    """-> {metric: [(cycle, pct_delta), ...]}"""
    res = {m: [] for m in METRICS}
    dirs = sorted(glob.glob(os.path.join(ROOT, "results/local-ab", f"seq*-{scenario}-baseline")))
    for bd in dirs:
        cyc = re.search(r"seq(\d+)-", os.path.basename(bd)).group(1)
        td = bd.replace("-baseline", "-tip")
        if not os.path.isdir(td):
            continue
        b, t = local_arm(bd), local_arm(td)
        if not b or not t:
            continue
        for m in METRICS:
            if len(b[m]) < 10 or len(t[m]) < 10:
                continue
            mb, mt = st.median(b[m]), st.median(t[m])
            if mb == 0:                       # e.g. local saveReceiptsMs is already 0
                continue
            res[m].append((int(cyc), 100.0 * (mt - mb) / mb))
    return res


def stored_threshold(d):
    """Boton JSONs are filtered at COLLECTION time and keep only aggregates -- there are
    no per-block rows to re-filter. The threshold used is therefore a property of the
    stored cycle and cannot be changed after the fact."""
    for f in glob.glob(os.path.join(d, "*_baseline.json")):
        try:
            return json.load(open(f)).get("threshold")
        except Exception:
            return None
    return None


def collect_boton(scenario, want_thr=0.9, excluded=None):
    res = {m: [] for m in METRICS}
    for fwd in sorted(glob.glob(os.path.join(ROOT, "results/boton", f"bseq*-{scenario}-fwd"))):
        cyc = re.search(r"bseq(\d+)-", os.path.basename(fwd)).group(1)
        rev = fwd[:-4] + "-rev"
        if not os.path.isdir(rev):
            continue
        # Never pool cycles collected at different thresholds. Indexer cycles 1-3 were
        # collected at 0.3 and averaged 44-50% utilization over ~26 qualifying blocks;
        # cycle 5 at 0.9 averaged 91.5% over 88. Mixing them compares half-empty blocks
        # against saturated ones, which is what produced an apparent +98% txExecutionMs
        # "regression" that vanished (-3%) once the populations matched.
        th = stored_threshold(fwd)
        if want_thr is not None and th is not None and abs(th - want_thr) > 1e-9:
            if excluded is not None:
                excluded.append((int(cyc), th))
            continue
        try:
            out = subprocess.run(
                [sys.executable, os.path.join(ROOT, "scripts/boton/crossover_estimate.py"), fwd, rev],
                capture_output=True, text=True, timeout=300).stdout
        except Exception:
            continue
        sec = out.split("=== p95")[0]         # p50 block only
        for ln in sec.splitlines():
            parts = ln.split()
            if len(parts) >= 4 and parts[0] in METRICS:
                try:
                    res[parts[0]].append((int(cyc), float(parts[-1].rstrip('%'))))
                except ValueError:
                    pass
    return res


def report(track, scenarios):
    print(f"\n{'='*74}\n  PAIRED CYCLES — {track}  (one delta per cycle, tip vs baseline, p50)\n{'='*74}")
    for sc in scenarios:
        excl = []
        res = collect_local(sc) if track == "local" else collect_boton(sc, 0.9, excl)
        if not any(res.values()):
            print(f"\n{sc}: no paired cycles found")
            continue
        print(f"\n{sc}")
        if excl:
            det = ", ".join(f"c{c} (thr {t})" for c, t in sorted(excl))
            print(f"  EXCLUDED, threshold mismatch vs 0.9: {det} — collected over a different "
                  f"block population; not poolable and not re-filterable (aggregates only).")
        print(f"  {'metric':<16}{'cycles':>7}{'median':>9}{'tip faster':>12}{'sign p':>9}   per-cycle")
        for m in METRICS:
            pts = sorted(res[m])
            if not pts:
                print(f"  {m:<16}{'-':>7}{'-':>9}{'-':>12}{'-':>9}   (no data)")
                continue
            ds = [d for _, d in pts]
            k, n, p = sign_test(ds)
            med = st.median(ds)
            ps = "-" if p is None else f"{p:.3f}"
            each = " ".join(f"c{c}:{d:+.0f}%" for c, d in pts)
            print(f"  {m:<16}{len(ds):>7}{med:>8.1f}%{f'{k}/{n}':>12}{ps:>9}   {each}")
        n_any = max(len(v) for v in res.values())
        if n_any < 6:
            print(f"  NOTE: {n_any} cycles — a unanimous sign test cannot reach p<0.05 below 6 "
                  f"cycles (2/2^6=0.031). Direction may be consistent; significance is not yet claimable.")


if __name__ == "__main__":
    track = sys.argv[1] if len(sys.argv) > 1 else "local"
    scen = sys.argv[2:] or ["mainnet", "ecdsa", "indexer", "calldata"]
    report(track, scen)
