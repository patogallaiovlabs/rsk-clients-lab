#!/usr/bin/env bash
# One replay of a scenario's blocks into one client, in Docker on this Mac, from an empty
# database. The unit a campaign repeats.
#
#   bin/replay-docker.sh rskj    <jar>          <scenario> <out-dir>
#   bin/replay-docker.sh rustock <image:tag>    <scenario> <out-dir>
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

CLIENT="${1:?client}"; ART="${2:?artifact}"; SCEN="${3:?scenario}"; OUT="${4:?out-dir}"
S=".scenarios.\"$SCEN\""
[ "$(cfg "$S")" != null ] || { echo "replay: unknown scenario '$SCEN'" >&2; exit 1; }
BLOCKS="$LAB/$(cfg "$S.blocks")"

GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
LIMITS=(--cpus "$(cfg .docker.cpus)" --memory "$(cfg .docker.memory)" --memory-swap "$(cfg .docker.memory)")
rm -rf "$OUT"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

if [ -z "${CLIENTSLAB_DOCKER_LOCK_HELD:-}" ]; then
  lock_acquire docker; trap 'lock_release docker' EXIT
fi
wait_for_disk

# The block file lives in its own volume, filled once per sample version and mounted
# read-only: bind-mounting large host files into Docker Desktop leaks their space.
SHA=$(jq -r .blocks_sha256 "$(dirname "$BLOCKS")/meta.json")
BVOL="clientslab-blocks-$SCEN-${SHA:0:12}"
if ! docker run --rm -v "$BVOL":/b alpine test -e /b/complete 2>/dev/null; then
  gunzip -c "$BLOCKS" | docker run -i --rm -v "$BVOL":/b alpine sh -c 'cat > /b/blocks.txt && touch /b/complete'
fi
VOL=clientslab-data
docker rm -f clientslab-replay >/dev/null 2>&1 || true
docker volume rm -f "$VOL" >/dev/null 2>&1 || true
docker volume create "$VOL" >/dev/null

T0=$(date +%s)
case "$CLIENT" in
rskj)
  # The flags perf-lab's replay passes (bin/replay.sh in rsk-perf-lab), minus its JMX agent.
  docker run --rm --name clientslab-replay "${LIMITS[@]}" \
    -v "$VOL":/data -v "$BVOL":/blocks:ro -v "$ART":/opt/rsk.jar:ro -v "$LAB/conf":/conf:ro \
    -w /data "$(cfg .docker.rskj_image)" \
    java $(cfg .docker.jvm_heap) \
      -Drsk.conf.file=/conf/rskj/rsk.conf -Dlogback.configurationFile=/conf/rskj/logback.xml \
      -Ddatabase.dir=/data/database -Dlogging.dir=/data/logs \
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
  ARGS=()
  while IFS= read -r a; do ARGS+=("$a"); done < <(jq -r '.import_args[]' "$LAB/clients/rustock.json" \
    | sed -e "s#{blocks}#/blocks/blocks.txt#; s#{datadir}#/data/db#; s#{breakdown}#/data/logs/block-breakdown.log#; s#{genesis}#/conf/$(basename "$(cfg .chain.genesis)")#; s#{flush}#$FLUSH#")
  docker run --rm --name clientslab-replay "${LIMITS[@]}" \
    -v "$VOL":/data -v "$BVOL":/blocks:ro -v "$LAB/conf":/conf:ro \
    "$ART" sh -c 'mkdir -p /data/logs && exec "$@"' -- rustock-cli "${ARGS[@]}" \
    > "$OUT/raw.log" 2>&1 || true
  ;;
*) echo "unknown client $CLIENT" >&2; exit 1 ;;
esac
WALL=$(( $(date +%s) - T0 ))
docker run --rm -v "$VOL":/from:ro -v "$OUT":/to alpine sh -c \
  'cp /from/logs/block-breakdown.log /to/ 2>/dev/null; for f in /from/logs/block-breakdown-*.log.gz; do [ -e "$f" ] && cp "$f" /to/; done; true'
docker volume rm -f "$VOL" >/dev/null 2>&1 || true

"$LAB/bin/check-run.sh" "$CLIENT" "$SCEN" "$OUT" "$WALL" "$ART"
