#!/usr/bin/env python3
"""Parse RSKj's block execute/persist breakdown debug logs and summarize timing.

Reads the `block connect breakdown best/alt:` (BlockChainImpl), `block execute
breakdown pre-RSKIP144/parallel:` (BlockExecutor), `mutable trie cache commit/save:`
(MutableTrieCache), and `trie store save root:` (TrieStoreImpl) debug lines described
in rsk/logback.xml, filters to blocks at/above a gas-utilization threshold, and reports
mean/p50/p95 per metric. Given a previously saved --save-json summary as --baseline,
prints a side-by-side before/after comparison with % change per metric.

Usage:
    # Compute and print this round's stats, save them for later comparison
    python3 scripts/analyze_block_breakdown.py --label round0 --save-json round0.json \
        logs/rsk.log logs/rskj-*.log.gz

    # Compute this round's stats and diff against a saved baseline
    python3 scripts/analyze_block_breakdown.py --label round1 --baseline round0.json \
        logs/rsk.log logs/rskj-*.log.gz
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
from pathlib import Path
from typing import Any

KV_RE = re.compile(r"(\w+)=(\S+)")

# message-prefix -> internal record kind
MARKERS = {
    "block connect breakdown best:": "connect",
    "block connect breakdown alt:": "connect",
    "block execute breakdown pre-RSKIP144:": "execute",
    "block execute breakdown parallel:": "execute",
    "block persistence step:": "persist_step",
    "mutable trie cache commit:": "trie_cache_commit",
    "mutable trie cache save:": "trie_cache_save",
    "trie store save root:": "trie_store_save",
}

# Per-block metrics pulled from "connect" and "execute" records (joined by block number).
PER_BLOCK_METRICS = [
    "totalMs",
    # preambleMs/processBestMs are emitted by b4a13038d onwards. Absent from a build
    # that predates it, in which case they simply never appear in the parsed output --
    # which is why a baseline+probe jar is needed to compare them at all.
    "preambleMs",
    "processBestMs",
    "executeMs",
    "initialValidationMs",
    "postExecuteValidationMs",
    "stateRootRegisterMs",
    "saveReceiptsMs",
    "onBestBlockMs",
    "onBlockMs",
    "switchChainMs",
    "extendAlternativeChainMs",
    "txExecutionMs",
    "statePersistMs",
    "parallelCompletionMs",
    "mergeMs",
    "sequentialTailMs",
    "receiptReorderMs",
]

# Global (not block-correlated -- these log lines carry no block number) metrics.
GLOBAL_METRICS = {
    "trie_cache_commit": ["durationMs"],
    "trie_cache_save": ["commitMs", "trieSaveMs", "totalMs"],
    "trie_store_save": ["durationMs"],
}


def open_maybe_gz(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", errors="replace")
    return open(path, "r", errors="replace")


def parse_kv(rest: str) -> dict[str, Any]:
    kv: dict[str, Any] = {}
    for m in KV_RE.finditer(rest):
        key, raw = m.group(1), m.group(2)
        try:
            kv[key] = int(raw)
        except ValueError:
            try:
                kv[key] = float(raw)
            except ValueError:
                kv[key] = raw
    return kv


def parse_files(paths: list[Path]) -> dict[str, list[dict[str, Any]]]:
    records: dict[str, list[dict[str, Any]]] = {
        "connect": [],
        "execute": [],
        "persist_step": [],
        "trie_cache_commit": [],
        "trie_cache_save": [],
        "trie_store_save": [],
    }
    for path in paths:
        with open_maybe_gz(path) as f:
            for line in f:
                for marker, kind in MARKERS.items():
                    idx = line.find(marker)
                    if idx == -1:
                        continue
                    kv = parse_kv(line[idx + len(marker):])
                    records[kind].append(kv)
                    break
    return records


def join_per_block(records: dict[str, list[dict[str, Any]]], gas_limit: int, threshold: float, min_block: int = 0):
    # Some workflows (e.g. the ExecuteBlocks CLI tool, used for deterministic replay
    # benchmarking) call BlockExecutor directly, bypassing BlockChainImpl entirely -- so
    # there's no "connect" record for those blocks, only "execute". Union both sources by
    # block number, preferring "connect" fields (its gasUsed/txCount reflect the final
    # connected block) but falling back to "execute" alone when connect is absent.
    connect_by_block = {}
    for rec in records["connect"]:
        if "block" in rec:
            connect_by_block[rec["block"]] = rec

    execute_by_block = {}
    for rec in records["execute"]:
        if "block" in rec:
            execute_by_block[rec["block"]] = rec

    all_blocks = set(connect_by_block) | set(execute_by_block)

    qualifying = []
    for block in all_blocks:
        if block < min_block:
            continue
        connect_rec = connect_by_block.get(block)
        exec_rec = execute_by_block.get(block)
        merged = dict(connect_rec) if connect_rec else {}
        if exec_rec:
            for k, v in exec_rec.items():
                merged.setdefault(k, v)
        gas_used = merged.get("gasUsed")
        if gas_used is None:
            continue
        if gas_used / gas_limit < threshold:
            continue
        qualifying.append(merged)
    return qualifying


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    k = (len(s) - 1) * (p / 100)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    if f == c:
        return s[f]
    return s[f] * (c - k) + s[c] * (k - f)


def trimmed_mean(values: list[float], cut: float = 0.1) -> float:
    """Mean after dropping the lowest and highest `cut` share. Robust to the occasional
    compaction spike like a median, but not stuck on whole milliseconds: block times are
    logged as integers, so two arms' medians are often exactly equal."""
    s = sorted(values)
    k = int(len(s) * cut)
    kept = s[k:len(s) - k] or s
    return sum(kept) / len(kept)


def stats_for(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"n": 0, "mean": None, "p50": None, "p95": None, "tmean10": None}
    return {
        "n": len(values),
        "mean": sum(values) / len(values),
        "p50": percentile(values, 50),
        "p95": percentile(values, 95),
        "tmean10": trimmed_mean(values),
    }


def summarize(paths: list[Path], gas_limit: int, threshold: float, min_block: int = 0) -> dict[str, Any]:
    records = parse_files(paths)
    qualifying = join_per_block(records, gas_limit, threshold, min_block)

    per_block_stats = {}
    # Plus any other per-block "...Ms" phase a client logs: rustock names some of its own
    # stages (see docs/timing-scope.md).
    extra = sorted({k for r in qualifying for k in r if k.endswith("Ms") and k not in PER_BLOCK_METRICS})
    for metric in PER_BLOCK_METRICS + extra:
        values = [r[metric] for r in qualifying if metric in r]
        s = stats_for(values)
        if s["n"] > 0:
            per_block_stats[metric] = s

    global_stats = {}
    for kind, metrics in GLOBAL_METRICS.items():
        for metric in metrics:
            values = [r[metric] for r in records[kind] if metric in r]
            s = stats_for(values)
            if s["n"] > 0:
                global_stats[f"{kind}.{metric}"] = s

    gas_used_values = [r["gasUsed"] for r in qualifying if "gasUsed" in r]
    return {
        "gas_limit": gas_limit,
        "threshold": threshold,
        "qualifying_blocks": len(qualifying),
        "total_connect_records": len(records["connect"]),
        "gas_utilization_mean": (sum(gas_used_values) / len(gas_used_values) / gas_limit) if gas_used_values else None,
        "per_block": per_block_stats,
        "global": global_stats,
    }


def fmt(v: float | None) -> str:
    return f"{v:.1f}" if v is not None else "n/a"


def print_summary(label: str, summary: dict[str, Any]) -> None:
    print(f"\n=== {label} ===")
    print(f"qualifying blocks (gasUsed/gasLimit >= {summary['threshold']}): "
          f"{summary['qualifying_blocks']} / {summary['total_connect_records']} total connect records"
          f" (mean utilization {fmt((summary['gas_utilization_mean'] or 0) * 100)}%)")
    print(f"\n{'metric':<28}{'n':>6}{'mean':>10}{'p50':>10}{'p95':>10}")
    for metric, s in summary["per_block"].items():
        print(f"{metric:<28}{s['n']:>6}{fmt(s['mean']):>10}{fmt(s['p50']):>10}{fmt(s['p95']):>10}")
    print()
    for metric, s in summary["global"].items():
        print(f"{metric:<28}{s['n']:>6}{fmt(s['mean']):>10}{fmt(s['p50']):>10}{fmt(s['p95']):>10}")


def print_comparison(baseline_label: str, baseline: dict[str, Any], after_label: str, after: dict[str, Any]) -> None:
    print(f"\n=== {baseline_label} vs {after_label} ===")
    print(f"{'metric':<28}{baseline_label + ' p50':>14}{after_label + ' p50':>14}{'delta %':>10}"
          f"{baseline_label + ' p95':>14}{after_label + ' p95':>14}{'delta %':>10}")

    all_metrics = list(baseline.get("per_block", {}).keys())
    all_metrics += [m for m in after.get("per_block", {}) if m not in all_metrics]
    all_metrics += [f"__global__{m}" for m in baseline.get("global", {}) if m not in baseline.get("per_block", {})]
    all_metrics += [f"__global__{m}" for m in after.get("global", {})
                    if f"__global__{m}" not in all_metrics and m not in after.get("per_block", {})]

    def get(summary, metric):
        if metric.startswith("__global__"):
            return summary.get("global", {}).get(metric[len("__global__"):])
        return summary.get("per_block", {}).get(metric)

    def pct_change(old, new):
        if old is None or new is None or old == 0:
            return None
        return (new - old) / old * 100

    for metric in all_metrics:
        b = get(baseline, metric)
        a = get(after, metric)
        b50 = b["p50"] if b else None
        a50 = a["p50"] if a else None
        b95 = b["p95"] if b else None
        a95 = a["p95"] if a else None
        d50 = pct_change(b50, a50)
        d95 = pct_change(b95, a95)
        display_name = metric[len("__global__"):] if metric.startswith("__global__") else metric
        print(f"{display_name:<28}{fmt(b50):>14}{fmt(a50):>14}{fmt(d50):>10}"
              f"{fmt(b95):>14}{fmt(a95):>14}{fmt(d95):>10}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="+", type=Path, help="rsk.log and/or rolled rskj-*.log.gz files")
    parser.add_argument("--gas-limit", type=int, default=25_000_000)
    parser.add_argument("--threshold", type=float, default=0.9, help="min gasUsed/gasLimit ratio to count as a 'full' block")
    parser.add_argument("--min-block", type=int, default=0, help="ignore blocks below this number (JIT warmup exclusion)")
    parser.add_argument("--label", default="this run")
    parser.add_argument("--save-json", type=Path, help="save this round's summary to a JSON file")
    parser.add_argument("--baseline", type=Path, help="a previously --save-json'd summary to compare against")
    args = parser.parse_args()

    summary = summarize(args.logs, args.gas_limit, args.threshold, args.min_block)
    print_summary(args.label, summary)

    if args.save_json:
        args.save_json.write_text(json.dumps(summary, indent=2))
        print(f"\nSaved summary to {args.save_json}")

    if args.baseline:
        baseline_summary = json.loads(args.baseline.read_text())
        print_comparison(args.baseline.stem, baseline_summary, args.label, summary)


if __name__ == "__main__":
    main()
