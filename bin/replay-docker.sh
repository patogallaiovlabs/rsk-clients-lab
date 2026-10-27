#!/usr/bin/env bash
# One replay of a scenario's blocks into one client, in Docker on this Mac, from an empty
# database (or a clone of the mainnet seed). The unit a campaign repeats.
#
#   bin/replay-docker.sh rskj    <jar>          <scenario> <out-dir> [options]
#   bin/replay-docker.sh rustock <image:tag>    <scenario> <out-dir> [options]
#
#   --blocks <file.gz> --hashes <file> --first N --last M
#       replay this block file instead of the scenario's sample, judged against these
#       reference hashes (the cross replay of a live arm, bin/check-live-arm.sh). The
#       scenario still says which database the run starts from and the fullness threshold.
#
# Both clients get the same container limits (config.json docker.cpus / docker.memory), the
# same block file (a read-only volume filled once per sample) and a fresh data volume.
# Without CLIENTSLAB_DOCKER_LOCK_HELD it takes the shared Docker slot itself.
#
# Writes <out-dir>/{raw.log, block-breakdown.log, hashes.txt, consensus.json, summary.json}.
# CONSENSUS: the run counts only if every block was imported, in order, with exactly the
# reference hashes (RSKj's own replay), and the log has one breakdown line per block.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CLIENT="${1:?client}"; ART="${2:?artifact}"; SCEN="${3:?scenario}"; OUT="${4:?out-dir}"; shift 4
S=".scenarios.\"$SCEN\""
[ "$(cfg "$S")" != null ] || { echo "replay: unknown scenario '$SCEN'" >&2; exit 1; }
BLOCKS="$LAB/$(cfg "$S.blocks")"; CUSTOM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --blocks) BLOCKS="$2"; CUSTOM=1 ;;
    --hashes) export CLIENTSLAB_HASHES="$2" ;;
    --first)  export CLIENTSLAB_FIRST="$2" ;;
    --last)   export CLIENTSLAB_LAST="$2" ;;
    *) echo "replay: unknown option $1" >&2; exit 2 ;;
  esac
  shift 2
done
[ -z "$CUSTOM" ] || [ -n "${CLIENTSLAB_HASHES:-}${CLIENTSLAB_FIRST:-}${CLIENTSLAB_LAST:-}" ] \
  || { echo "replay: --blocks needs --hashes, --first and --last" >&2; exit 2; }
DB=$(cfg "$S.db"); [ "$DB" = null ] && DB=empty

GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
MEM=$(cfg .docker.memory); [ "$DB" = mainnet ] && MEM=$(cfg .docker.mainnet_memory)
LIMITS=(--cpus "$(cfg .docker.cpus)" --memory "$MEM" --memory-swap "$MEM")
rm -rf "$OUT"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

if [ -z "${CLIENTSLAB_DOCKER_LOCK_HELD:-}" ]; then
  lock_acquire docker; trap 'lock_release docker' EXIT
fi
wait_for_disk

# The sample's volume is filled once per sample version; a custom block file gets a
# volume of its own, refilled every time.
if [ -n "$CUSTOM" ]; then
  BVOL="clientslab-blocks-custom"; blocks_volume "$BLOCKS" "$BVOL" fresh
else
  SHA=$(jq -r .blocks_sha256 "$(dirname "$BLOCKS")/meta.json")
  BVOL="clientslab-blocks-${SCEN//@/-at-}-${SHA:0:12}"; blocks_volume "$BLOCKS" "$BVOL"
fi
docker rm -f clientslab-replay >/dev/null 2>&1 || true
db_setup "$CLIENT" "$DB" "clientslab-run-$CLIENT" /data
trap 'db_drop; [ -n "${CLIENTSLAB_DOCKER_LOCK_HELD:-}" ] || lock_release docker' EXIT
RSKJ_DB=/data/database; [ "$DB" = mainnet ] && RSKJ_DB=/data/test/local-regtest/database
# rustock's converted seed is a data dir itself (state/convert-mainnet.sh), so its clone is
# mounted as one; an empty run gets a subdirectory of the fresh volume.
ARGS_KEY=import_args; RUSTOCK_DB=/data/db
[ "$DB" = mainnet ] && { ARGS_KEY=mainnet_import_args; RUSTOCK_DB=/data; }

T0=$(date +%s)
case "$CLIENT" in
rskj)
  # The flags perf-lab's replay passes (bin/replay.sh in rsk-perf-lab), minus its JMX agent.
  docker run --rm --name clientslab-replay "${LIMITS[@]}" \
    "${DATA[@]}" -v "$BVOL":/blocks:ro -v "$ART":/opt/rsk.jar:ro -v "$LAB/conf":/conf:ro \
    -w /data "$(cfg .docker.rskj_image)" \
    java $(cfg .docker.jvm_heap) \
      -Drsk.conf.file=/conf/rskj/rsk.conf -Dlogback.configurationFile=/conf/rskj/logback.xml \
      -Ddatabase.dir=$RSKJ_DB -Dlogging.dir=/data/logs $MAINNET_PROPS \
      -Dminer.server.enabled=false -Dminer.client.timedMine=false -Dminer.server.skipPowValidation=true \
      -Dpeer.privateKey=AFF6A83FEFFF6FF0C9F6FFFE41F6FF10D9FFFF3F41FFCFBF41F6FF90DFFFFF81 -Dpeer.port=50601 \
      -Dtargetgaslimit="$GAS" -Dsystem.profiling.enabled=true -Dblockchain.flushNumberOfBlocks="$FLUSH" \
      -Dgenesis="/conf/$(basename "$(cfg .chain.genesis)")" \
      -Dlogging.stdout=INFO -Dlogging.file=INFO -Dlogging=INFO \
      -cp /opt/rsk.jar co.rsk.cli.tools.ConnectBlocks --regtest --file /blocks/blocks.txt \
    > "$OUT/raw.log" 2>&1 || true
  ;;
rustock)
  # Import arguments come from clients/rustock.json (the harness adapter's CLI).
  rustock_args "$ARGS_KEY" "s#{blocks}#/blocks/blocks.txt#; s#{datadir}#$RUSTOCK_DB#; s#{breakdown}#/data/logs/block-breakdown.log#; s#{genesis}#/conf/$(basename "$(cfg .chain.genesis)")#; s#{flush}#$FLUSH#"
  docker run --rm --name clientslab-replay "${LIMITS[@]}" \
    "${DATA[@]}" -v "$BVOL":/blocks:ro -v "$LAB/conf":/conf:ro \
    "$ART" sh -c 'mkdir -p /data/logs && exec "$@"' -- rustock-cli "${ARGS[@]}" \
    > "$OUT/raw.log" 2>&1 || true
  ;;
*) echo "unknown client $CLIENT" >&2; exit 1 ;;
esac
WALL=$(( $(date +%s) - T0 ))
docker run --rm "${DATA[@]}" -v "$OUT":/to alpine sh -c \
  'cp /data/logs/block-breakdown.log /to/ 2>/dev/null; for f in /data/logs/block-breakdown-*.log.gz; do [ -e "$f" ] && cp "$f" /to/; done; true'
db_drop

"$LAB/bin/check-run.sh" "$CLIENT" "$SCEN" "$OUT" "$WALL" "$ART"
