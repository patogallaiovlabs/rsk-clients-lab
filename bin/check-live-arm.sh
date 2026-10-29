#!/usr/bin/env bash
# Check and summarize one finished live arm, after its cross replay.
#
#   bin/check-live-arm.sh <client> <scenario> <out-dir>
#
# Reads what bin/live-arm.sh left in <out-dir> and <out-dir>/cross/consensus.json (the
# arm's blocks replayed into the other client by bin/replay-docker.sh --blocks), and
# writes consensus.json and summary.json in the shape bin/check-run.sh writes, so
# bin/stats.py reads live and replay runs alike. The arm counts (consensus_ok) only if all
# four checks of docs/live-mining-plan.md section 4 hold:
#   1. cross replay: every block connected in the other client with the hash the miner gave it;
#   2. the node's own blocks: one breakdown line per exported block, all above the start
#      height, with the export's hashes (the log starts empty); a block of its own that the
#      node replaced at the same height (a sibling) is allowed and kept out of the timing;
#   3. k6: the scenario's success rate (config.json live.k6_success_metric per k6 option,
#      read from the k6 summary) at least live.k6_min_success_pct;
#   4. at least live.min_qualifying_blocks blocks at least threshold full, after the first
#      live.min_block blocks of the arm.
# Exit 0 when the arm counts, 3 when the cross replay failed (a consensus finding, which
# stops the campaign), 1 when the arm measured nothing and is discarded.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CLIENT="$1"; SCEN="$2"; OUT="$3"
S=".scenarios.\"$SCEN\""
THRESH=$(cfg "$S.threshold"); GAS=$(cfg .chain.gas_limit); OPT=$(cfg "$S.k6_option")
MIN_BLOCK=$(cfg .live.min_block); MIN_Q=$(cfg .live.min_qualifying_blocks)
METRIC=$(cfg ".live.k6_success_metric[\"$OPT\"]"); MIN_PCT=$(cfg ".live.k6_min_success_pct[\"$OPT\"]")
[ -s "$OUT/arm.json" ] || { echo "check-live-arm: no arm.json in $OUT" >&2; exit 1; }
START=$(jq -r .start_height "$OUT/arm.json"); END=$(jq -r .end_height "$OUT/arm.json")
WALL=$(jq -r .wall_s "$OUT/arm.json"); ART=$(jq -r .artifact "$OUT/arm.json")
EXPECTED=$(( END - START )); [ "$EXPECTED" -ge 0 ] || EXPECTED=0

# --- 2. the node's own blocks -----------------------------------------------------------
# The breakdown line carries block=<n> hash=<h> for every block connected as best; the
# export (hashes.txt) is what the cross replay was judged against.
BD=( "$OUT"/block-breakdown.log )
shopt -s nullglob; ROT=( "$OUT"/block-breakdown-*.log.gz ); shopt -u nullglob
{ cat "${BD[@]}" 2>/dev/null; [ ${#ROT[@]} -eq 0 ] || gzcat "${ROT[@]}"; } \
  | grep 'block connect breakdown best:' \
  | sed -E 's/.*block connect breakdown best: block=([0-9]+) hash=([0-9a-fx]+).*/\1 \2/; s/ 0x/ /' \
  | sort -n -k1,1 > "$OUT/log-hashes.txt" || true
RECORDS=$(wc -l < "$OUT/log-hashes.txt" | tr -d ' ')
BELOW=$(awk -v s="$START" '$1 <= s' "$OUT/log-hashes.txt" | wc -l | tr -d ' ')
# A miner may connect two blocks of its own at one height within milliseconds and keep the
# second (RSKj's timed miner, 2026-10-29-c1 cycle 6: two "best" lines for #9003625, 44 ms
# apart). The replaced one is the node's own block, inside the arm's range, and is not in
# the export: it is listed as a sibling, kept out of the timing, and does not discard the
# arm. Anything else in the log that the export lacks (a block past the end height, or at
# a height with no exported record) still does.
sort -k2,2 "$OUT/hashes.txt" > "$OUT/.exp"; sort -k2,2 "$OUT/log-hashes.txt" > "$OUT/.log"
MISSING=$(join -v1 -j2 "$OUT/.exp" "$OUT/.log" | wc -l | tr -d ' ')
join -v2 -j2 "$OUT/.exp" "$OUT/.log" | awk '{print $2, $1}' | sort -n -k1,1 > "$OUT/extra-hashes.txt"
rm -f "$OUT/.exp" "$OUT/.log"
SIBLINGS=$(awk -v s="$START" -v e="$END" 'NR==FNR {h[$1]=1; next} $1 > s && $1 <= e && h[$1]' \
  "$OUT/hashes.txt" "$OUT/extra-hashes.txt" | wc -l | tr -d ' ')
EXTRA=$(wc -l < "$OUT/extra-hashes.txt" | tr -d ' ')
LOG_OK=false
[ "$RECORDS" -gt 0 ] && [ "$BELOW" = 0 ] && [ "$MISSING" = 0 ] && [ "$EXTRA" = "$SIBLINGS" ] && LOG_OK=true
FIRST_BAD=$(diff "$OUT/hashes.txt" "$OUT/log-hashes.txt" 2>/dev/null | grep -m1 '^[<>]' || true)
[ $LOG_OK = true ] && FIRST_BAD=""
# The sibling's lines leave the breakdown input the analyzer and the totals read.
if [ "$SIBLINGS" -gt 0 ]; then
  { cat "${BD[@]}" 2>/dev/null; [ ${#ROT[@]} -eq 0 ] || gzcat "${ROT[@]}"; } \
    | grep -v -F -f <(awk '{print "hash=" $2}' "$OUT/extra-hashes.txt") > "$OUT/block-breakdown.canonical.log" || true
  BD=( "$OUT/block-breakdown.canonical.log" ); ROT=()
fi

# --- 1. cross replay ----------------------------------------------------------------------
CROSS="$OUT/cross/consensus.json"; CROSS_OK=false; CROSS_JSON=null; CROSS_RAN=false
if [ -s "$CROSS" ]; then
  CROSS_RAN=true; CROSS_JSON=$(cat "$CROSS")
  jq -e .consensus_ok "$CROSS" >/dev/null && CROSS_OK=true
fi

# --- 3. k6 -------------------------------------------------------------------------------
# Option 7 writes its custom summary (results/<test>.json, metric.rate); option 14 prints
# k6's default summary, "<metric>....: NN.NN%  a out of b". Crossed k6 thresholds are
# recorded, not judged: the rate is the gate.
K6=$(python3 - "$OUT" "$METRIC" "$MIN_PCT" <<'PY'
import json, os, re, sys
out, metric, min_pct = sys.argv[1], sys.argv[2], float(sys.argv[3])
rate = src = None
p = os.path.join(out, "k6-summary.json")
if os.path.exists(p):
    try:
        m = json.load(open(p)).get("metrics", {}).get(metric, {})
        if "rate" in m:
            rate, src = 100.0 * float(m["rate"]), "k6-summary.json"
    except ValueError:
        pass
log = os.path.join(out, "k6.log")
text = open(log, errors="replace").read() if os.path.exists(log) else ""
if rate is None:
    hits = re.findall(r"^\s*" + re.escape(metric) + r"\.*: ([0-9.]+)%", text, re.M)
    if hits:
        rate, src = float(hits[-1]), "k6.log"
crossed = len(re.findall(r"^\s*✗ '", text, re.M)) > 0 or "THRESHOLDS FAILED" in text \
    or "some thresholds have failed" in text
print(json.dumps({"metric": metric, "success_pct": None if rate is None else round(rate, 3), "min_pct": min_pct,
                  "source": src, "ok": rate is not None and rate >= min_pct,
                  "thresholds_crossed": crossed, "k6_runs": text.count("=== Iteration ")}))
PY
)
K6_OK=$(echo "$K6" | jq -r .ok)

# --- 4. qualifying blocks, and the per-block statistics stats.py reads -------------------
# min-block is relative to the start height, so the first min_block blocks of an arm are
# dropped on both chains (k6 deploys its contracts there; the JIT warms up).
Q=0; TOTALS='{"tx_count":0,"gas_used":0}'
if [ "$RECORDS" -gt 0 ]; then
  python3 "$LAB/bin/analyze_block_breakdown.py" --gas-limit "$GAS" --threshold "$THRESH" \
    --min-block $((START + MIN_BLOCK)) --label "$CLIENT-$SCEN-live" --save-json "$OUT/summary.json" \
    "${BD[@]}" ${ROT[@]+"${ROT[@]}"} > "$OUT/analyze.txt" 2>&1 || true
  Q=$(jq -r '.qualifying_blocks // 0' "$OUT/summary.json" 2>/dev/null || echo 0)
  TOTALS=$({ cat "${BD[@]}" 2>/dev/null; [ ${#ROT[@]} -eq 0 ] || gzcat "${ROT[@]}"; } | python3 -c "
import re, sys, json
tx = gas = 0
for l in sys.stdin:
    m = re.search(r'block connect breakdown best: block=(\d+).*?txCount=(\d+).*?gasUsed=(\d+)', l)
    if m and int(m.group(1)) > $START:
        tx += int(m.group(2)); gas += int(m.group(3))
print(json.dumps({'tx_count': tx, 'gas_used': gas}))")
fi
Q_OK=false; [ "$Q" -ge "$MIN_Q" ] && Q_OK=true

OK=false
[ $CROSS_OK = true ] && [ $LOG_OK = true ] && [ "$K6_OK" = true ] && [ $Q_OK = true ] && OK=true
jq -n --argjson ok $OK --argjson records "$RECORDS" --argjson expected "$EXPECTED" --arg first_bad "$FIRST_BAD" \
  --argjson wall "$WALL" --arg client "$CLIENT" --arg artifact "$ART" --argjson start "$START" --argjson end "$END" \
  --argjson cross_ran $CROSS_RAN --argjson cross_ok $CROSS_OK --argjson log_ok $LOG_OK --argjson q_ok $Q_OK --argjson siblings "$SIBLINGS" \
  --argjson k6 "$K6" --argjson q "$Q" --argjson min_q "$MIN_Q" --argjson cross "$CROSS_JSON" --argjson totals "$TOTALS" \
  '{consensus_ok:$ok, kind:"live", records:$records, expected:$expected, first_difference:$first_bad,
    wall_s:$wall, client:$client, artifact:$artifact, start_height:$start, end_height:$end,
    checks:{cross_replay:$cross_ok, own_blocks:$log_ok, k6:$k6.ok, qualifying:$q_ok}, own_siblings:$siblings,
    k6_success_pct:$k6.success_pct, k6_min_success_pct:$k6.min_pct, k6_metric:$k6.metric,
    qualifying_blocks:$q, min_qualifying_blocks:$min_q, tx_count:$totals.tx_count, gas_used:$totals.gas_used,
    cross_replay:(if $cross_ran then $cross else "not run" end)}' > "$OUT/consensus.json"
# summary.json: the analyzer's per_block plus the arm's own numbers, for report.py.
if [ -s "$OUT/summary.json" ]; then
  jq --argjson c "$(cat "$OUT/consensus.json")" \
    '.live = {blocks_mined:$c.expected, qualifying_blocks:$c.qualifying_blocks, tx_count:$c.tx_count,
              gas_used:$c.gas_used, k6_success_pct:$c.k6_success_pct, k6_metric:$c.k6_metric,
              cross_replay_ok:$c.checks.cross_replay}' "$OUT/summary.json" > "$OUT/summary.json.tmp" \
    && mv "$OUT/summary.json.tmp" "$OUT/summary.json"
fi
cat "$OUT/consensus.json"
[ "$OK" = true ] && exit 0
[ $CROSS_RAN = true ] && [ $CROSS_OK = false ] && exit 3
exit 1
