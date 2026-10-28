#!/usr/bin/env bash
# The Boton part of a campaign for one scenario: cycles of two counterbalanced slots.
#
#   bin/boton-campaign.sh <campaign-id> <scenario>
#
#   fwd slot: box A replays into RSKj,    box B into rustock   (at the same time)
#   rev slot: box A replays into rustock, box B into RSKj
#
# A sequential campaign (campaign.json "clients", docs/mainnet-db-plan.md) runs only the
# listed clients' halves of each slot; the other half comes in a later pass.
#
# Each box runs one client at a time from an empty database, natively (the RSKj jar on the
# box's JDK 17, the rustock binary built in Ubuntu 22.04). Holding a box for a few
# minutes per slot, the campaign checks between cycles whether perf-lab waits with a more
# urgent priority (its 6-boton is 0, its replays 1; campaigns hold at 2) and hands the boxes
# over, keeping the cycles it finished.
#
# Writes campaigns/<id>/raw/boton/<scenario>/c<k>-{fwd,rev}/{A,B}/ (bin/check-run.sh output).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CID="${1:?campaign id}"; SCEN="${2:?scenario}"
C="$LAB/campaigns/$CID/campaign.json"
JAR=$(jq -r .builds.rskj "$C"); RUSTOCK=$(jq -r '.builds["rustock-boton"]' "$C")
CYCLES=$(jq -r .cycles "$C"); MAX=$(jq -r .max_cycles "$C")
D="$LAB/campaigns/$CID/raw/boton/$SCEN"; mkdir -p "$D"
S=".scenarios.\"$SCEN\""
GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
PRIO=$(cfg .boton.box_priority); R=$(cfg .boton.remote_dir)
GEN=$(basename "$(cfg .chain.genesis)")
CLIENTS=" $(jq -r '(.clients // ["rskj","rustock"]) | join(" ")' "$C") "
wanted() { case "$CLIENTS" in *" $1 "*) return 0 ;; esac; return 1; }
# Scenarios on the mainnet DB (config.json "db": "mainnet") start from a hard-link clone of
# the seed staged on the box: perf-lab's RSKj seed (bin/boton-seed-upload.sh there) for
# RSKj, this lab's converted seed for rustock. node.props carries the seed's activations.
DB=$(cfg "$S.db // \"empty\"")
PERF="$LAB/$(cfg .mainnet_seed.perf_lab)"
RSKJ_SEED=/var/lib/rsk/mainnet-seed/seed/test/local-regtest/database
RUSTOCK_SEED=/var/lib/rsk/rustock-seed
# The clone must live on the seed's volume (hard links do not cross file systems); the
# run directory is on the root disk.
DBDIR=db; [ "$DB" = mainnet ] && DBDIR=/var/lib/rsk/clientslab-db
MAINNET_PROPS=""; [ "$DB" = mainnet ] && MAINNET_PROPS="-Ddatabase.rocksdb.maxOpenFiles=1000 $(cat "$PERF/database-seed/seeds/mainnet/node.props")"

lock_boxes() { box_lock A "$PRIO"; box_lock B "$PRIO"; }
unlock_boxes() { box_unlock B; box_unlock A; }
lock_boxes; trap unlock_boxes EXIT

# Inputs, uploaded once per box and reused (rsync skips what did not change).
upload() {
  local box="$1" h; h=$(box_host "$box")
  local rs=(rsync -a -e "ssh ${BOX_SSH[*]}")
  box_ssh "$box" "mkdir -p $R/samples/$SCEN $R/bin $R/conf/rskj $R/run"
  "${rs[@]}" "$LAB/$(cfg "$S.blocks")" "ubuntu@$h:$R/samples/$SCEN/blocks.txt.gz"
  "${rs[@]}" "$JAR" "ubuntu@$h:$R/bin/rsk.jar"
  "${rs[@]}" "$RUSTOCK" "ubuntu@$h:$R/bin/rustock-cli"
  "${rs[@]}" "$LAB/conf/rskj/" "ubuntu@$h:$R/conf/rskj/"
  "${rs[@]}" "$LAB/$(cfg .chain.genesis)" "ubuntu@$h:$R/conf/$GEN"
  box_ssh "$box" "cd $R/samples/$SCEN && { [ blocks.txt -nt blocks.txt.gz ] || gunzip -c blocks.txt.gz > blocks.txt; }
    chmod +x ~/$R/bin/rustock-cli; ~/$R/bin/rustock-cli --version >/dev/null"
}
upload A; upload B

# The rustock import arguments, with the box's paths filled in.
# Absolute paths, not $HOME: printf %q escapes the dollar, and that backslash
# reaches the remote shell, so rustock looks for a file named '$HOME/...'.
REMOTE_HOME=/home/ubuntu
ARGS_KEY=import_args; [ "$DB" = mainnet ] && ARGS_KEY=mainnet_import_args
RUSTOCK_ARGS=$(jq -r ".$ARGS_KEY[]" "$LAB/clients/rustock.json" | sed -e \
  "s#{blocks}#$REMOTE_HOME/$R/samples/$SCEN/blocks.txt#; s#{datadir}#$DBDIR#; s#{breakdown}#logs/block-breakdown.log#; s#{genesis}#$REMOTE_HOME/$R/conf/$GEN#; s#{flush}#$FLUSH#" \
  | while IFS= read -r a; do printf '%q ' "$a"; done)

# One run on one box. Prints the wall time in seconds.
run_on() {
  local box="$1" client="$2" out="$3" cmd
  case "$client" in
    rskj) cmd="java $(cfg .docker.jvm_heap) -Drsk.conf.file=\$HOME/$R/conf/rskj/rsk.conf \
      -Dlogback.configurationFile=\$HOME/$R/conf/rskj/logback.xml -Ddatabase.dir=$DBDIR -Dlogging.dir=logs \
      -Dminer.server.enabled=false -Dminer.client.timedMine=false -Dminer.server.skipPowValidation=true \
      -Dpeer.privateKey=AFF6A83FEFFF6FF0C9F6FFFE41F6FF10D9FFFF3F41FFCFBF41F6FF90DFFFFF81 -Dpeer.port=50601 \
      -Dtargetgaslimit=$GAS $MAINNET_PROPS -Dsystem.profiling.enabled=true -Dblockchain.flushNumberOfBlocks=$FLUSH \
      -Dgenesis=\$HOME/$R/conf/$GEN -Dlogging.stdout=INFO -Dlogging.file=INFO -Dlogging=INFO \
      -cp \$HOME/$R/bin/rsk.jar co.rsk.cli.tools.ConnectBlocks --regtest --file \$HOME/$R/samples/$SCEN/blocks.txt" ;;
    rustock) cmd="\$HOME/$R/bin/rustock-cli $RUSTOCK_ARGS" ;;
  esac
  mkdir -p "$out"
  box_quiesce "$box" || { echo "box $box still runs a node, load or replay" >&2; return 1; }
  local t0; t0=$(date +%s)
  # sudo for the clean-up: a profiling run as root (perf record) leaves root-owned files
  # there, and an unprivileged delete then fails and the run never starts (2026-10-27).
  local clone=""
  if [ "$DB" = mainnet ]; then
    # RocksDB never rewrites a table: link the .sst files, copy the files it does rewrite.
    local seed; seed=$([ "$client" = rskj ] && echo "$RSKJ_SEED" || echo "$RUSTOCK_SEED")
    clone="[ -d $seed ] || { echo 'no seed at $seed on this box' >&2; exit 1; }
      sudo rm -rf $DBDIR; sudo cp -al $seed/. $DBDIR/ && sudo find $DBDIR -type f ! -name '*.sst' -exec sh -c 'for f; do cp -a \"\$f\" \"\$f.copy\" && mv -f \"\$f.copy\" \"\$f\"; done' _ {} +
      sudo find $DBDIR \\( -type d -o -type f ! -name '*.sst' \\) -exec chown ubuntu:ubuntu {} +;"
  fi
  box_ssh "$box" "set -e; cd $R/run; sudo find . -mindepth 1 -delete; mkdir -p logs; $clone exec $cmd" > "$out/raw.log" 2>&1 || true
  echo $(( $(date +%s) - t0 )) > "$out/wall_s"
  rsync -a -e "ssh ${BOX_SSH[*]}" --include='block-breakdown*.log*' --exclude='*' \
    "ubuntu@$(box_host "$box"):$R/run/logs/" "$out/" || true
  echo "box $box ($(box_host "$box"))" > "$out/host.txt"
}

# Both boxes at once; then check both runs. Exit 3 on a consensus failure.
slot() {
  local dir="$1" client_a="$2" client_b="$3"
  mkdir -p "$dir"
  local pa="" pb=""
  wanted "$client_a" && { rm -rf "$dir/A"; run_on A "$client_a" "$dir/A" & pa=$!; }
  wanted "$client_b" && { rm -rf "$dir/B"; run_on B "$client_b" "$dir/B" & pb=$!; }
  [ -z "$pa" ] || wait $pa; [ -z "$pb" ] || wait $pb
  local box client art
  for box in A B; do
    client=$([ $box = A ] && echo "$client_a" || echo "$client_b")
    wanted "$client" || continue
    art=$([ "$client" = rskj ] && echo "$JAR" || echo "$RUSTOCK")
    "$LAB/bin/check-run.sh" "$client" "$SCEN" "$dir/$box" "$(cat "$dir/$box/wall_s")" "$art" >/dev/null \
      || { echo "boton $SCEN $(basename "$dir") box $box ($client): $(cat "$dir/$box/consensus.json")" > "$D/consensus-failure.txt"; exit 3; }
  done
  log "boton $SCEN $(basename "$dir"): A $client_a $(jq .wall_s "$dir/A/consensus.json" 2>/dev/null || echo -) s, B $client_b $(jq .wall_s "$dir/B/consensus.json" 2>/dev/null || echo -) s"
}

k=0
while [ $k -lt "$MAX" ]; do
  k=$((k + 1))
  done_run() { [ -s "$1/consensus.json" ] && jq -e .consensus_ok "$1/consensus.json" >/dev/null; }
  complete=1
  { ! wanted rskj || { done_run "$D/c$k-fwd/A" && done_run "$D/c$k-rev/B"; }; } || complete=""
  { ! wanted rustock || { done_run "$D/c$k-fwd/B" && done_run "$D/c$k-rev/A"; }; } || complete=""
  [ -z "$complete" ] || continue
  slot "$D/c$k-fwd" rskj rustock
  slot "$D/c$k-rev" rustock rskj
  if [ $k -ge "$CYCLES" ]; then
    V=$(python3 "$LAB/bin/stats.py" boton "$D" "$SCEN" | jq -r .verdict)
    log "boton $SCEN after $k cycles: $V"
    [ "$V" = extend ] || break
    # One client alone cannot be judged; the other half decides later.
    case "$CLIENTS" in " rskj rustock "|" rustock rskj ") ;; *) break ;; esac
  fi
  if box_wanted A "$PRIO" || box_wanted B "$PRIO"; then
    log "boton: perf-lab waits for a box with a more urgent priority; handing both over"
    unlock_boxes; sleep 30; lock_boxes
  fi
done
