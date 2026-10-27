#!/usr/bin/env bash
# One live mining arm: one client mines its own blocks under k6 load for live.arm_minutes,
# in Docker on this Mac, from an empty database or a clone of the mainnet seed. The unit a
# live campaign repeats (docs/live-mining-plan.md, section 5).
#
#   bin/live-arm.sh rskj    <jar>       <scenario> <out-dir>
#   bin/live-arm.sh rustock <image:tag> <scenario> <out-dir>
#
# RSKj runs as perf-lab's live arms do (bin/live-arm-mainnet.sh there): the perflab-runtime
# image's entrypoint with IS_MINER=true, timed mining at a 10 s median, the lab's rsk.conf
# and logback, genesis_25M.json, a flush every 10 blocks, the account rate limiter off, RPC
# on 4444. rustock runs clients/rustock.json live_args (mainnet_live_args on the seed) and
# is told evm_startMining once RPC answers; RSKj mines by itself. k6 runs on the host from
# the rskj-k6-tests checkout (config.json mainnet_seed.k6), the scenario's k6_option.
#
# Same container limits for both (config.json live.cpus, live.memory, live.mainnet_memory).
# One node at a time: without CLIENTSLAB_DOCKER_LOCK_HELD the arm takes the shared Docker
# slot as a long holder with CLIENTSLAB_PRIORITY, as a campaign cycle does.
#
# Writes <out-dir>/{raw.log, block-breakdown.log, k6.log, k6-summary.json, blocks.txt.gz,
# hashes.txt, arm.json}. Whether the arm counts is bin/check-live-arm.sh's call, after the
# cross replay (bin/lab.py runs both).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CLIENT="${1:?client}"; ART="${2:?artifact}"; SCEN="${3:?scenario}"; OUT="${4:?out-dir}"
S=".scenarios.\"$SCEN\""
[ "$(cfg "$S")" != null ] || { echo "live-arm: unknown scenario '$SCEN'" >&2; exit 1; }
OPT=$(cfg "$S.k6_option"); [ "$OPT" != null ] || { echo "live-arm: scenario '$SCEN' has no k6_option" >&2; exit 1; }
DB=$(cfg "$S.db"); [ "$DB" = null ] && DB=empty
MIN=$(cfg .live.arm_minutes); GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
PORT=$(cfg .live.rpc_port); HEAP=$(cfg .docker.jvm_heap)
MEM=$(cfg .live.memory); [ "$DB" = mainnet ] && MEM=$(cfg .live.mainnet_memory)
LIMITS=(--cpus "$(cfg .live.cpus)" --memory "$MEM" --memory-swap "$MEM")
K6="$LAB/$(cfg .mainnet_seed.k6)"; RUNTIME=$(cfg .mainnet_seed.runtime_image)
GEN="/conf/$(basename "$(cfg .chain.genesis)")"; CT=clientslab-live
[ -x "$K6/infinite.sh" ] || { echo "live-arm: no k6 suite at $K6" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

if [ -z "${CLIENTSLAB_DOCKER_LOCK_HELD:-}" ]; then
  lock_acquire docker "long:${CLIENTSLAB_PRIORITY:-9999999999}"
fi
cleanup() {
  quiesce_load || true
  docker rm -f "$CT" >/dev/null 2>&1 || true
  db_drop
  [ -n "${CLIENTSLAB_DOCKER_LOCK_HELD:-}" ] || lock_release docker
}
trap cleanup EXIT
wait_for_disk
quiesce_load || exit 1
docker rm -f "$CT" >/dev/null 2>&1 || true

rpc() { curl -s -m 5 -X POST "http://localhost:$PORT" -H 'Content-Type: application/json' -d "$1"; }
height() { rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | python3 -c "import json,sys; print(int(json.load(sys.stdin)['result'], 16))"; }

# The database, and the height the node starts at. The breakdown log and the export are
# written inside the data mount and copied out once the node has stopped.
START=0; [ "$DB" = mainnet ] && START=$(seed_tip)
case "$CLIENT" in
rskj)
  MNT=/var/lib/rsk; db_setup rskj "$DB" clientslab-live-rskj "$MNT"
  LOGDIR="$MNT/test/local-regtest"; EXPORT="$MNT/export.txt"
  # A fresh volume belongs to root; the node runs as the image's rsk user.
  if [ "$DB" != mainnet ]; then
    RSK_UID=$(docker run --rm --entrypoint id "$RUNTIME" -u); RSK_GID=$(docker run --rm --entrypoint id "$RUNTIME" -g)
    docker run --rm "${DATA[@]}" alpine chown "$RSK_UID:$RSK_GID" "$MNT"
  fi
  ;;
rustock)
  MNT=/data; db_setup rustock "$DB" clientslab-live-rustock "$MNT"
  LOGDIR="$MNT/logs"; EXPORT="$MNT/export.txt"
  # As in replay-docker.sh: the converted seed is a data dir itself, an empty run gets a
  # subdirectory of the fresh volume.
  ARGS_KEY=live_args; EXPORT_KEY=export_args; RUSTOCK_DB=/data/db
  [ "$DB" = mainnet ] && { ARGS_KEY=mainnet_live_args; EXPORT_KEY=mainnet_export_args; RUSTOCK_DB=/data; }
  SUBST="s#{datadir}#$RUSTOCK_DB#; s#{breakdown}#$LOGDIR/block-breakdown.log#; s#{genesis}#$GEN#; s#{flush}#$FLUSH#; s#{wallet}#/conf/rustock-wallet.keys#; s#{coinbase}#$(cfg .live.mining_coinbase)#; s#{file}#$EXPORT#"
  ;;
*) echo "unknown client $CLIENT" >&2; exit 1 ;;
esac

# rskj_tool <class> <opts> [docker run flags...]: the runtime image's entrypoint with the
# flags of perf-lab's live arms (bin/live-arm-mainnet.sh); IS_MINER=true adds the timed
# miner at a 10 s median, the coinbase from miner.coinbase.secret=miner1.
rskj_tool() {
  local cls="$1" opts="$2"; shift 2
  docker run "$@" "${DATA[@]}" -v "$ART":/usr/local/lib/rsk/rsk.jar:ro -v "$LAB/conf":/conf:ro \
    -e MINER_ID=1 -e IS_MINER="${IS_MINER:-false}" -e WIRE_DELAY=0 -e BLOCK_GAS_LIMIT="$GAS" \
    -e GENESIS_FILE="$GEN" -e FLUSH_BLOCKS="$FLUSH" -e DEFAULT_JVM_OPTS="$HEAP" \
    -e RSKJ_SYS_PROPS="-Drsk.conf.file=/conf/rskj/rsk.conf -Dlogging.dir=test/local-regtest/ -Dtransaction.accountTxRateLimit.enabled=false -Dpeer.discovery.enabled=false" \
    -e RSKJ_LOG_PROPS="-Dlogback.configurationFile=/conf/rskj/logback.xml -Dlogging.stdout=OFF -Dlogging.file=INFO -Dlogging=INFO $MAINNET_PROPS" \
    -e RSKJ_CLASS="$cls" -e RSKJ_OPTS="$opts" "$RUNTIME"
}

T0=$(date +%s); STARTED=$(date -u +%FT%TZ); touch "$OUT/.started"
log "live arm $CLIENT $SCEN: k6 option $OPT, $DB database from #$START, $MIN min"
case "$CLIENT" in
rskj)
  IS_MINER=true rskj_tool co.rsk.Start "--regtest" -d --name "$CT" "${LIMITS[@]}" -p "$PORT:4444" >/dev/null
  ;;
rustock)
  rustock_args "$ARGS_KEY" "$SUBST"
  docker run -d --name "$CT" "${LIMITS[@]}" "${DATA[@]}" -v "$LAB/conf":/conf:ro -p "$PORT:4444" \
    "$ART" sh -c 'mkdir -p /data/logs && exec "$@"' -- rustock-cli "${ARGS[@]}" >/dev/null
  ;;
esac

# RPC up (opening the 186 GiB seed takes minutes), at the height the database ends.
for i in $(seq 1 360); do
  rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q result && break
  [ "$(docker inspect -f '{{.State.Running}}' "$CT")" = true ] \
    || { log "node exited during startup"; docker logs --tail 30 "$CT" > "$OUT/raw.log" 2>&1; exit 1; }
  sleep 5
done
H0=$(height) || { log "RPC never came up"; exit 1; }
[ "$H0" = "$START" ] || { log "node opened at #$H0, expected #$START"; exit 1; }
MINING=""
if [ "$CLIENT" = rustock ]; then
  # RSKj mines by itself. rustock's miner is started over RPC; harmless if --mine-timed
  # already started it, and the answer is kept for the record.
  MINING=$(rpc '{"jsonrpc":"2.0","method":"evm_startMining","params":[],"id":1}')
  log "evm_startMining: $MINING"
fi

# k6 on the host, as perf-lab's local-ab.sh starts it. Option 7 sizes its phases to
# DURATION; option 14 runs for an hour of its own and is stopped with the arm.
( cd "$K6" && RPC_URL="http://localhost:$PORT" DURATION="${MIN}m" nohup ./infinite.sh "$OPT" > "$OUT/k6.log" 2>&1 < /dev/null & )
sleep 20
# The load must really be running: a missing node or npm leaves infinite.sh looping on
# errors while the node mines empty blocks (perf-lab, 2026-10-23).
if grep -qE "No such file or directory|command not found|Cannot find module" "$OUT/k6.log"; then
  log "the k6 load cannot start: $(grep -m1 -E 'No such file|not found|Cannot find' "$OUT/k6.log")"; exit 1
fi
N=$(pgrep -f "[i]nfinite.sh" | wc -l | tr -d ' ')
[ "$N" = 1 ] || { log "expected exactly one k6 load driver, found $N"; exit 1; }

# The arm. The node must stay up and the host disk above its floor.
T_END=$(( T0 + MIN * 60 )); FLOOR=$(cfg .machines.min_free_gb); n=0
while [ "$(date +%s)" -lt "$T_END" ]; do
  sleep 60; n=$((n + 1))
  [ "$(docker inspect -f '{{.State.Running}}' "$CT")" = true ] \
    || { log "node exited during the arm"; docker logs --tail 30 "$CT" > "$OUT/raw.log" 2>&1; exit 1; }
  if [ "$(df -k "$LAB" | awk 'NR==2{print int($4/1048576)}')" -lt "$FLOOR" ]; then
    log "under ${FLOOR} GB free on the host; stopping the arm"; exit 1
  fi
  [ $((n % 5)) = 0 ] && log "live arm $CLIENT $SCEN: $n min, height $(height 2>/dev/null || echo '?')"
done
quiesce_load || true
H=$(height) || { log "RPC gone at the end of the arm"; docker logs --tail 30 "$CT" > "$OUT/raw.log" 2>&1; exit 1; }
docker stop -t 120 "$CT" >/dev/null; docker logs "$CT" > "$OUT/raw.log" 2>&1 || true
docker rm -f "$CT" >/dev/null 2>&1 || true
WALL=$(( $(date +%s) - T0 ))
# The k6 summary file, when the scenario writes one (option 7 does; option 14 only prints).
find "$K6/results" -name '*.json' -newer "$OUT/.started" 2>/dev/null | head -1 \
  | while IFS= read -r f; do cp "$f" "$OUT/k6-summary.json"; done

# The node's own blocks, exported from the stopped database for the cross replay, in
# RSKj's ExportBlocks format (number,hash,... per line).
FROM=$((START + 1))
if [ "$H" -ge "$FROM" ]; then
  case "$CLIENT" in
  rskj)
    rskj_tool co.rsk.cli.tools.ExportBlocks "--regtest --fromBlock $FROM --toBlock $H --file $EXPORT" \
      --rm "${LIMITS[@]}" > "$OUT/export.log" 2>&1 || true ;;
  rustock)
    rustock_args "$EXPORT_KEY" "$SUBST; s#{from}#$FROM#; s#{to}#$H#"
    docker run --rm "${LIMITS[@]}" "${DATA[@]}" -v "$LAB/conf":/conf:ro "$ART" rustock-cli "${ARGS[@]}" \
      > "$OUT/export.log" 2>&1 || true ;;
  esac
fi
docker run --rm "${DATA[@]}" -v "$OUT":/to alpine sh -c "cp $LOGDIR/block-breakdown.log /to/ 2>/dev/null; \
  for f in $LOGDIR/block-breakdown-*.log.gz; do [ -e \"\$f\" ] && cp \"\$f\" /to/; done; \
  [ -e $EXPORT ] && gzip -9 -c $EXPORT > /to/blocks.txt.gz; true"
db_drop
if [ -s "$OUT/blocks.txt.gz" ]; then gzcat "$OUT/blocks.txt.gz" | awk -F, '{print $1, $2}' > "$OUT/hashes.txt"; else : > "$OUT/hashes.txt"; fi
NB=$(wc -l < "$OUT/hashes.txt" | tr -d ' ')
jq -n --arg client "$CLIENT" --arg artifact "$ART" --arg scenario "$SCEN" --arg db "$DB" --argjson k6_option "$OPT" \
  --argjson start "$START" --argjson end "$H" --argjson exported "$NB" --argjson minutes "$MIN" --argjson wall "$WALL" \
  --arg started "$STARTED" --arg cpus "$(cfg .live.cpus)" --arg memory "$MEM" --arg heap "$HEAP" --arg mining "$MINING" \
  '{kind:"live", client:$client, artifact:$artifact, scenario:$scenario, db:$db, k6_option:$k6_option,
    start_height:$start, end_height:$end, blocks_mined:($end-$start), blocks_exported:$exported,
    arm_minutes:$minutes, wall_s:$wall, started_at:$started, cpus:$cpus, memory:$memory, jvm_heap:$heap,
    evm_startMining:$mining}' > "$OUT/arm.json"
log "live arm $CLIENT $SCEN: blocks $FROM..$H ($((H - START)) mined, $NB exported) in $WALL s"
