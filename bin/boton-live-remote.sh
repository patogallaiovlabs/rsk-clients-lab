#!/usr/bin/env bash
# Runs ON a Boton box: one live mining arm, natively, from an empty database. The box's
# half of a slot of bin/boton-live-slot.sh, which uploads this script with the inputs and
# writes $R/arm.env (CLIENT, ARTIFACT, SCEN, OPT, MIN, GAS, FLUSH, HEAP, GEN, GPR).
#
#   ~/clientslab/bin/boton-live-remote.sh      (cwd and paths: $HOME/clientslab)
#
# Same shape as bin/live-arm.sh in Docker: the node mines its own blocks under the k6
# suite (uploaded to $R/k6-tests, run on the box against 127.0.0.1:4444) for MIN minutes,
# the load is stopped, rustock's miner too, the node is stopped and its blocks exported in
# RSKj's ExportBlocks format for the cross replay on the Mac. RSKj runs the flags of the
# runtime image's entrypoint with IS_MINER=true (docker/runtime/Dockerfile) plus the lab's
# rsk.conf and logback; rustock runs clients/rustock.json live_args with the box's paths.
#
# Writes $R/run/out/{raw.log, block-breakdown.log, k6.log, k6-summary.json, blocks.txt.gz,
# hashes.txt, export.log, arm.json, arm.log}, which the slot script copies back.
set -euo pipefail
R="$HOME/clientslab"; RUN="$R/run"; OUT="$RUN/out"
. "$R/arm.env"
mkdir -p "$OUT" "$RUN/logs"
ulimit -n 65536
log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$OUT/arm.log"; }
rpc() { curl -s -m 5 -X POST http://127.0.0.1:4444 -H 'Content-Type: application/json' -d "$1"; }
height() { local h; h=$(rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r .result); [ -n "$h" ] && [ "$h" != null ] && echo $((h)); }
MAINNET_PROPS=""
RSKJ_PROPS="-Drsk.conf.file=$R/conf/rskj/rsk.conf -Dlogback.configurationFile=$R/conf/rskj/logback.xml
  -Ddatabase.dir=$RUN/db -Dlogging.dir=$RUN/logs -Dlogging.stdout=OFF -Dlogging.file=INFO -Dlogging=INFO
  -Dgenesis=$R/conf/$GEN -Dtransaction.accountTxRateLimit.enabled=false -Dpeer.discovery.enabled=false
  -Dminer.server.skipPowValidation=true -Dwire.simulatedDelay=0
  -DtxLoad.blockTargetGas=$GAS -DtxLoad.primaryTxGas=$GAS -Drpc.gasEstimationCap=$GAS -Dtargetgaslimit=$GAS
  -Dsystem.profiling.enabled=true -Dblockchain.flushNumberOfBlocks=$FLUSH
  -Drpc.providers.web.http.bind_address=127.0.0.1 $MAINNET_PROPS"
# The miner flags the runtime image adds for IS_MINER=true with MINER_ID=1.
RSKJ_MINER="-Dminer.server.enabled=true -Dminer.client.timedMine=true -Dminer.coinbase.secret=miner1
  -Dpeer.privateKey=AFF6A83FEFFF6FF0C9F6FFFE41F6FF10D9FFFF3F41FFCFBF41F6FF90DFFFFF91 -Dpeer.port=50501
  -Dminer.client.medianBlockTime=10s"
read_args() { local a=(); while IFS= read -r l; do a+=("$l"); done < "$1"; ARGS=("${a[@]}"); }

START=0; STARTED=$(date -u +%FT%TZ); T0=$(date +%s); touch "$OUT/.started"
log "live arm $CLIENT $SCEN on $(hostname): k6 option $OPT, empty database, $MIN min"
case "$CLIENT" in
rskj)
  # shellcheck disable=SC2086
  nohup java $HEAP $RSKJ_PROPS $RSKJ_MINER -cp "$R/bin/rsk.jar" co.rsk.Start --regtest > "$OUT/raw.log" 2>&1 < /dev/null &
  NODE=$! ;;
rustock)
  read_args "$R/rustock-live.args"
  nohup "$R/bin/rustock-cli" "${ARGS[@]}" > "$OUT/raw.log" 2>&1 < /dev/null &
  NODE=$! ;;
*) log "unknown client $CLIENT"; exit 1 ;;
esac
stop_node() {
  kill -0 "$NODE" 2>/dev/null || return 0
  kill -TERM "$NODE" 2>/dev/null || true
  local i; for i in $(seq 1 120); do kill -0 "$NODE" 2>/dev/null || return 0; sleep 1; done
  log "node did not stop in 120 s; killing it"; kill -KILL "$NODE" 2>/dev/null || true; sleep 2
}
stop_load() {
  pkill -f "[i]nfinite.sh" 2>/dev/null || true; pkill -f "[k]6 run" 2>/dev/null || true
  local i; for i in $(seq 1 60); do pgrep -f "[k]6 run|[i]nfinite.sh" >/dev/null || return 0; sleep 1; done
  log "k6 load still running after 60 s"; return 1
}
trap 'stop_load || true; stop_node' EXIT

for i in $(seq 1 120); do
  rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q result && break
  kill -0 "$NODE" 2>/dev/null || { log "node exited during startup"; exit 1; }
  sleep 5
done
H0=$(height) || { log "RPC never came up"; exit 1; }
[ "$H0" -ge "$START" ] && [ "$H0" -le $((START + 3)) ] || { log "node opened at #$H0, expected #$START"; exit 1; }
MINING=""
if [ "$CLIENT" = rustock ]; then
  MINING=$(rpc '{"jsonrpc":"2.0","method":"evm_startMining","params":[],"id":1}')
  log "evm_startMining: $MINING"
fi

( cd "$R/k6-tests" && RPC_URL=http://127.0.0.1:4444 DURATION="${MIN}m" GAS_PRICE_RULE="$GPR" \
    setsid nohup ./infinite.sh "$OPT" > "$OUT/k6.log" 2>&1 < /dev/null & )
sleep 20
if grep -qE "No such file or directory|command not found|Cannot find module" "$OUT/k6.log"; then
  log "the k6 load cannot start: $(grep -m1 -E 'No such file|not found|Cannot find' "$OUT/k6.log")"; exit 1
fi
N=$(pgrep -f "[i]nfinite.sh" | wc -l | tr -d ' ')
[ "$N" = 1 ] || { log "expected exactly one k6 load driver, found $N"; exit 1; }

T_END=$(( T0 + MIN * 60 )); n=0
while [ "$(date +%s)" -lt "$T_END" ]; do
  sleep 60; n=$((n + 1))
  kill -0 "$NODE" 2>/dev/null || { log "node exited during the arm"; exit 1; }
  if [ "$(df -k "$HOME" | awk 'NR==2{print int($4/1048576)}')" -lt 5 ]; then
    log "under 5 GB free on the box; stopping the arm"; exit 1
  fi
  [ $((n % 5)) = 0 ] && log "live arm $CLIENT $SCEN: $n min, height $(height 2>/dev/null || echo '?')"
done
stop_load || true
[ "$CLIENT" = rustock ] && log "evm_stopMining: $(rpc '{"jsonrpc":"2.0","method":"evm_stopMining","params":[],"id":1}')"
H=$(height) || { log "RPC gone at the end of the arm"; exit 1; }
stop_node
WALL=$(( $(date +%s) - T0 ))
find "$R/k6-tests/results" -name '*.json' -newer "$OUT/.started" 2>/dev/null | head -1 \
  | while IFS= read -r f; do cp "$f" "$OUT/k6-summary.json"; done

FROM=$((START + 1)); EXPORT="$RUN/export.txt"
if [ "$H" -ge "$FROM" ]; then
  case "$CLIENT" in
  rskj)
    # shellcheck disable=SC2086
    java $HEAP $RSKJ_PROPS -Dminer.server.enabled=false -Dminer.client.timedMine=false \
      -cp "$R/bin/rsk.jar" co.rsk.cli.tools.ExportBlocks --regtest --fromBlock "$FROM" --toBlock "$H" --file "$EXPORT" \
      > "$OUT/export.log" 2>&1 || true ;;
  rustock)
    sed -e "s#{from}#$FROM#; s#{to}#$H#" "$R/rustock-export.args" > "$RUN/export.args"
    read_args "$RUN/export.args"
    "$R/bin/rustock-cli" "${ARGS[@]}" > "$OUT/export.log" 2>&1 || true ;;
  esac
fi
cp "$RUN"/logs/block-breakdown.log "$OUT/" 2>/dev/null || true
for f in "$RUN"/logs/block-breakdown-*.log.gz; do [ -e "$f" ] && cp "$f" "$OUT/"; done
if [ -s "$EXPORT" ]; then gzip -9 -c "$EXPORT" > "$OUT/blocks.txt.gz"; awk -F, '{print $1, $2}' "$EXPORT" > "$OUT/hashes.txt"; else : > "$OUT/hashes.txt"; fi
NB=$(wc -l < "$OUT/hashes.txt" | tr -d ' ')
jq -n --arg client "$CLIENT" --arg artifact "$ARTIFACT" --arg scenario "$SCEN" --arg db empty --argjson k6_option "$OPT" \
  --argjson start "$START" --argjson last "$H" --argjson exported "$NB" --argjson minutes "$MIN" --argjson wall "$WALL" \
  --arg started "$STARTED" --arg host "$(hostname)" --arg cpus "$(nproc)" --arg memory "$(free -g | awk 'NR==2{print $2 "g"}')" \
  --arg heap "$HEAP" --arg mining "$MINING" \
  '{kind:"live", where:"boton", client:$client, artifact:$artifact, scenario:$scenario, db:$db, k6_option:$k6_option,
    start_height:$start, end_height:$last, blocks_mined:($last-$start), blocks_exported:$exported,
    arm_minutes:$minutes, wall_s:$wall, started_at:$started, host:$host, cpus:$cpus, memory:$memory, jvm_heap:$heap,
    evm_startMining:$mining}' > "$OUT/arm.json"
log "live arm $CLIENT $SCEN: blocks $FROM..$H ($((H - START)) mined, $NB exported) in $WALL s"
