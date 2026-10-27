#!/usr/bin/env bash
# Mine a block sample on top of perf-lab's mainnet seed with RSKj under one k6 scenario,
# until enough blocks are full, and export it with its reference hashes.
#
#   bin/build-mainnet-sample.sh <name> <k6-option> [min-qualifying] [threshold] [max-hours]
#   -> samples/<name>/{blocks.txt.gz, reference_hashes.txt, meta.json}, blocks seed_tip+1..H
#
# The seed, its clone tooling and the k6 suite live in rsk-perf-lab (config.json
# "mainnet_seed"): this is the one place the lab reads another checkout, because the seed
# is 186 GiB and exists once. The node runs as a perf-lab mainnet live arm does
# (bin/live-arm-mainnet.sh there): a hard-link clone of the seed, node.props activations,
# 1000 open files, 10 GB memory, timed mining at a 10 s median, 25M gas, integration build.
# Holds the Docker slot for the whole run.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
NAME="${1:?usage: build-mainnet-sample.sh <name> <k6-option> [min-qualifying] [threshold] [max-hours]}"
OPT="${2:?}"; WANT="${3:-200}"; THR="${4:-0.9}"; MAX_H="${5:-3}"
OUTD="$LAB/samples/$NAME"; mkdir -p "$OUTD"
PERF="$LAB/$(cfg .mainnet_seed.perf_lab)"
SEED_DIR="$PERF/database-seed"; META="$SEED_DIR/seeds/mainnet/meta.json"; PROPS="$SEED_DIR/seeds/mainnet/node.props"
K6="$PERF/repos/rskj-k6-tests"; VOL=$(cfg .mainnet_seed.volume); CLONE="clientslab-sample"; CT="clientslab-sample"
TIP=$(jq -r .seed_tip "$META"); GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
JAR=$(bin/build-client.sh rskj "$(jq -r .ref "$LAB/clients/rskj.json")" | tail -1)
SHA=$(git -C "$LAB/clients/rskj" rev-parse HEAD)
RUNTIME=$(cfg .mainnet_seed.runtime_image)

rpc() { curl -s -m 5 -X POST http://localhost:4444 -H 'Content-Type: application/json' -d "$1"; }
height() { rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | python3 -c "import json,sys;print(int(json.load(sys.stdin)['result'],16))"; }
quiesce_load() { pkill -f "[i]nfinite.sh" 2>/dev/null || true; pkill -f "[k]6 run" 2>/dev/null || true; sleep 2; }

node() {  # node <class> <opts> [docker run flags...]
  local cls="$1" opts="$2"; shift 2
  docker run --rm "$@" \
    --mount "type=volume,src=$VOL,dst=/var/lib/rsk,volume-subpath=$CLONE" \
    -v "$JAR":/usr/local/lib/rsk/rsk.jar:ro -v "$LAB/conf":/conf:ro \
    -e MINER_ID=1 -e IS_MINER="${IS_MINER:-false}" -e WIRE_DELAY=0 -e BLOCK_GAS_LIMIT="$GAS" \
    -e GENESIS_FILE="/conf/$(basename "$(cfg .chain.genesis)")" -e FLUSH_BLOCKS="$FLUSH" \
    -e DEFAULT_JVM_OPTS="-Xms4G -Xmx4G" \
    -e RSKJ_SYS_PROPS="-Drsk.conf.file=/conf/rskj/rsk.conf -Dlogging.dir=test/local-regtest/ -Dtransaction.accountTxRateLimit.enabled=false -Dpeer.discovery.enabled=false" \
    -e RSKJ_LOG_PROPS="-Dlogback.configurationFile=/conf/rskj/logback.xml -Dlogging.stdout=OFF -Dlogging.file=INFO -Dlogging=INFO -Ddatabase.rocksdb.maxOpenFiles=1000 $(cat "$PROPS")" \
    -e RSKJ_CLASS="$cls" -e RSKJ_OPTS="$opts" "$RUNTIME"
}

lock_acquire docker "long:-1"
cleanup() { quiesce_load; docker rm -f "$CT" >/dev/null 2>&1 || true; lock_release docker; }
trap cleanup EXIT
quiesce_load; docker rm -f "$CT" >/dev/null 2>&1 || true
docker run --rm -v "$VOL":/v alpine rm -rf "/v/$CLONE"
log "sample '$NAME': cloning the mainnet seed (tip #$TIP)"
( cd "$SEED_DIR" && SEED=mainnet SIM_ROOT="$PERF" PERF_LAB_LIB="$PERF/bin/lib.sh" RUNTIME_IMAGE="$RUNTIME" ./clone.sh "$CLONE" )

log "sample '$NAME': mining on the seed with ${SHA:0:9} under k6 option $OPT until $WANT blocks >= ${THR} full"
IS_MINER=true node co.rsk.Start "--regtest" -d --name "$CT" -p 4444:4444 -p 4445:4445 --cpus 4 --memory 10g >/dev/null
for i in $(seq 1 360); do
  rpc '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q result && break
  [ "$(docker inspect -f '{{.State.Running}}' "$CT")" = true ] || { log "node exited during startup"; docker logs --tail 30 "$CT"; exit 1; }
  sleep 5
done
H0=$(height); [ "$H0" = "$TIP" ] || { log "node opened at #$H0, expected the seed tip #$TIP"; exit 1; }
( cd "$K6" && RPC_URL=http://localhost:4444 DURATION="${MAX_H}h" nohup ./infinite.sh "$OPT" > "$OUTD/k6.log" 2>&1 < /dev/null & )

T_END=$(( $(date +%s) + MAX_H * 3600 ))
while :; do
  sleep 60
  Q=$(docker exec "$CT" sh -c 'cat /var/lib/rsk/test/local-regtest/block-breakdown*.log 2>/dev/null' \
      | python3 -c "
import re, sys
n = 0
for l in sys.stdin:
    m = re.search(r'block connect breakdown best: block=(\d+).*?gasUsed=(\d+)', l)
    if m and int(m.group(1)) > $TIP and int(m.group(2)) >= $THR * $GAS: n += 1
print(n)")
  H=$(height)
  log "sample '$NAME': height $H, $Q qualifying blocks"
  [ "$Q" -ge "$WANT" ] && break
  [ "$(date +%s)" -ge "$T_END" ] && { log "sample '$NAME': gave up after ${MAX_H}h with $Q qualifying"; exit 1; }
done
quiesce_load
docker stop -t 120 "$CT" >/dev/null
docker rm -f "$CT" >/dev/null 2>&1 || true

FROM=$((TIP + 1))
log "sample '$NAME': exporting blocks $FROM..$H"
node co.rsk.cli.tools.ExportBlocks "--regtest --fromBlock $FROM --toBlock $H --file /var/lib/rsk/export.txt" > "$OUTD/export.log" 2>&1
docker run --rm -v "$VOL":/v alpine cat "/v/$CLONE/export.txt" | gzip -9 > "$OUTD/blocks.txt.gz"
NB=$(gzcat "$OUTD/blocks.txt.gz" | wc -l | tr -d ' ')
[ "$NB" = $((H - TIP)) ] || { log "sample '$NAME': exported $NB blocks, expected $((H - TIP))"; exit 1; }
gzcat "$OUTD/blocks.txt.gz" | awk -F, '{print $1, $2}' > "$OUTD/reference_hashes.txt"
jq -n --arg name "$NAME" --argjson blocks "$NB" --argjson from "$FROM" --argjson to "$H" --argjson q "$Q" \
  --arg sha "$(shasum -a 256 "$OUTD/blocks.txt.gz" | cut -d' ' -f1)" --argjson opt "$OPT" --argjson thr "$THR" \
  --arg mined "$SHA" --arg tip "$(jq -r .seed_tip_hash "$META")" --arg at "$(date -u +%FT%TZ)" \
  '{name:$name, db:"mainnet", blocks:$blocks, first_block:$from, last_block:$to, blocks_sha256:$sha,
    seed_tip:($from-1), seed_tip_hash:$tip, k6_option:$opt, threshold:$thr, qualifying_at_build:$q,
    mined_with:$mined, built:$at,
    node:"single miner on a clone of the mainnet seed, 4 CPUs, 4 GB heap, 10 GB memory, node.props, maxOpenFiles 1000, timed mining 10 s median"}' \
  > "$OUTD/meta.json"
docker run --rm -v "$VOL":/v alpine rm -rf "/v/$CLONE"
log "sample '$NAME': $NB blocks ($Q qualifying), $FROM..$H"
# Record the block range in config.json so replay-docker.sh and check-run.sh know it.
jq --arg s "$NAME" --argjson f "$FROM" --argjson t "$H" '.scenarios[$s].first_block = $f | .scenarios[$s].last_block = $t' \
  "$LAB/config.json" > "$LAB/config.json.tmp" && mv "$LAB/config.json.tmp" "$LAB/config.json"
