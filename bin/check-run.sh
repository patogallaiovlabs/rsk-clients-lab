#!/usr/bin/env bash
# Check and summarize one finished replay, wherever it ran.
#
#   bin/check-run.sh <client> <scenario> <out-dir> <wall-s> <artifact>
#
# Reads <out-dir>/block-breakdown.log (and rotated parts), writes hashes.txt, consensus.json
# and summary.json, and exits non-zero unless the run counts: every block of the scenario
# connected as best, in order, with exactly the reference hashes (RSKj's own replay).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CLIENT="$1"; SCEN="$2"; OUT="$3"; WALL="$4"; ART="$5"
S=".scenarios.\"$SCEN\""
REF="$LAB/$(cfg "$S.reference_hashes")"; THRESH=$(cfg "$S.threshold"); GAS=$(cfg .chain.gas_limit)
EXPECTED=$(( $(cfg "$S.last_block") - $(cfg "$S.first_block") + 1 ))

# --- consensus check -------------------------------------------------------------------
# The breakdown line carries block=<n> hash=<h> for every block each client connected as best.
BD=( "$OUT"/block-breakdown.log )
shopt -s nullglob; ROT=( "$OUT"/block-breakdown-*.log.gz ); shopt -u nullglob
{ cat "${BD[@]}" 2>/dev/null; [ ${#ROT[@]} -eq 0 ] || gzcat "${ROT[@]}"; } \
  | grep 'block connect breakdown best:' \
  | sed -E 's/.*block connect breakdown best: block=([0-9]+) hash=([0-9a-fx]+).*/\1 \2/; s/ 0x/ /' \
  | sort -n -k1,1 > "$OUT/hashes.txt" || true
RECORDS=$(wc -l < "$OUT/hashes.txt" | tr -d ' ')
MATCH=false; cmp -s "$OUT/hashes.txt" "$REF" && MATCH=true
FIRST_BAD=$(diff <(cut -d' ' -f1,2 "$REF") "$OUT/hashes.txt" | grep -m1 '^[<>]' || true)
OK=false; [ "$MATCH" = true ] && [ "$RECORDS" = "$EXPECTED" ] && OK=true
jq -n --argjson ok $OK --argjson records "$RECORDS" --argjson expected "$EXPECTED" \
  --arg first_bad "$FIRST_BAD" --argjson wall "$WALL" --arg client "$CLIENT" --arg artifact "$ART" \
  '{consensus_ok:$ok, records:$records, expected:$expected, first_difference:$first_bad,
    wall_s:$wall, client:$client, artifact:$artifact}' > "$OUT/consensus.json"

if [ -s "$OUT/hashes.txt" ]; then
  python3 "$LAB/bin/analyze_block_breakdown.py" --gas-limit "$GAS" --threshold "$THRESH" \
    --label "$CLIENT-$SCEN" --save-json "$OUT/summary.json" \
    "${BD[@]}" ${ROT[@]+"${ROT[@]}"} > "$OUT/analyze.txt" 2>&1 || true
fi
cat "$OUT/consensus.json"
[ "$OK" = true ]
