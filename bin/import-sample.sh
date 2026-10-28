#!/usr/bin/env bash
# Import a block sample mined elsewhere on a seed database and make it replayable from genesis.
#
#   bin/import-sample.sh <name> <seed.tar.gz> <blocks_2_to_N.txt.gz> <reference_hashes.txt>
#
# Such a sample holds blocks 2..N on top of a seed database that already holds block 1 (an RSKj
# RocksDB). rustock cannot read that database, so both clients here start from an empty one
# and replay 1..N: block 1 is exported from the seed with RSKj's ExportBlocks and prepended.
# Writes samples/<name>/{blocks.txt.gz, reference_hashes.txt, meta.json}; the block file is
# gitignored, meta.json records its sha256.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NAME="${1:?name}"; SEED="${2:?seed}"; BLOCKS="${3:?blocks}"; HASHES="${4:?hashes}"
OUT="$LAB/samples/$NAME"; mkdir -p "$OUT"
JAR=$(bin/build-client.sh rskj "$(jq -r .ref "$LAB/clients/rskj.json")" | tail -1)
TMP="$STATE/import-$NAME"; rm -rf "$TMP"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
tar xzf "$SEED" -C "$TMP"

# A JVM on this Mac while a benchmark runs would be noise in it: wait for the Docker slot.
lock_acquire docker
( cd "$TMP" && java -Xmx2G \
    -Drsk.conf.file="$LAB/conf/rskj/rsk.conf" -Dgenesis="$LAB/$(cfg .chain.genesis)" \
    -Ddatabase.dir=./test/local-regtest/database -Dlogging.dir=./logs \
    -cp "$JAR" co.rsk.cli.tools.ExportBlocks --regtest --fromBlock 1 --toBlock 1 --file "$TMP/block1.txt" ) \
  > "$TMP/export.log" 2>&1 || { lock_release docker; cat "$TMP/export.log" >&2; exit 1; }
lock_release docker

[ "$(wc -l < "$TMP/block1.txt" | tr -d ' ')" = 1 ] || { echo "export of block 1 failed" >&2; exit 1; }
[ "$(cut -d, -f1 "$TMP/block1.txt")" = 1 ] || { echo "exported line is not block 1" >&2; exit 1; }
{ cat "$TMP/block1.txt"; gzcat "$BLOCKS"; } | gzip -9 > "$OUT/blocks.txt.gz"
{ awk -F, '{print $1, $2}' "$TMP/block1.txt"; cat "$HASHES"; } > "$TMP/hashes.txt"
mv "$TMP/hashes.txt" "$OUT/reference_hashes.txt"

N=$(gzcat "$OUT/blocks.txt.gz" | wc -l | tr -d ' ')
LAST=$(gzcat "$OUT/blocks.txt.gz" | tail -1 | cut -d, -f1)
[ "$N" = "$LAST" ] || { echo "sample has $N lines but ends at block $LAST" >&2; exit 1; }
cmp -s <(gzcat "$OUT/blocks.txt.gz" | awk -F, '{print $1, $2}') "$OUT/reference_hashes.txt" \
  || { echo "block file and reference hashes disagree" >&2; exit 1; }
jq -n --arg name "$NAME" --argjson blocks "$N" --arg sha "$(shasum -a 256 "$OUT/blocks.txt.gz" | cut -d' ' -f1)" \
  --arg seed "$(basename "$SEED")" --arg src "$(basename "$BLOCKS")" --arg jar "$(basename "$JAR")" \
  --arg at "$(date -u +%FT%TZ)" \
  '{name:$name, blocks:$blocks, first_block:1, last_block:$blocks, blocks_sha256:$sha,
    source:{seed:$seed, blocks:$src, block1_exported_with:$jar}, imported:$at}' > "$OUT/meta.json"
log "sample $NAME: blocks 1..$N, block 1 $(cut -d, -f2 "$TMP/block1.txt" | cut -c1-12)"
