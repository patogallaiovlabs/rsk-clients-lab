#!/usr/bin/env bash
# One live slot on the Boton boxes: both boxes mine at the same time, natively, under the k6
# suite running on each box. The Boton unit a live campaign repeats (docs/live-mining-plan.md,
# section 5):
#
#   bin/boton-live-slot.sh <campaign-id> <scenario> <arm-dir-A> <client-A> <arm-dir-B> <client-B>
#   bin/boton-live-slot.sh <campaign-id> <scenario> <slot-dir> <client-A> <client-B>
#                          (the arms go to <slot-dir>/A and <slot-dir>/B)
#
# Empty-database scenarios are counterbalanced: the fwd slot runs RSKj on box A and rustock
# on box B, the rev slot swaps them. Scenarios on the mainnet seed run one client on both
# boxes at once (the boxes hold one client's seed at a time, bin/boton-seed.sh), each arm
# from a hard-link clone of that seed, into the same fwd/rev layout: RSKj to fwd/A and
# rev/B, rustock to rev/A and fwd/B. A client "-" skips that box.
#
# Takes both box locks at config.json boton.box_priority for the slot (another lab's more
# urgent work gets the boxes between slots), uploads the inputs once per box (rsync skips
# what did not change: the RSKj jar, the rustock binary, the lab's conf, the k6 suite with
# its npm install), then runs bin/boton-live-remote.sh on each box and copies its output
# back to the arm dir in the shape bin/live-arm.sh writes. The cross replay and the checks
# run on the Mac afterwards (bin/lab.py _boton_check). CLIENTSLAB_ARM_MINUTES overrides
# live.arm_minutes (smoke tests).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CID="${1:?campaign id}"; SCEN="${2:?scenario}"
if [ $# -eq 5 ]; then OA="$3/A"; CA="$4"; OB="$3/B"; CB="$5"
else OA="${3:?arm dir A}"; CA="${4:?client on A}"; OB="${5:?arm dir B}"; CB="${6:?client on B}"; fi
C="$LAB/campaigns/$CID/campaign.json"
JAR=$(jq -r .builds.rskj "$C"); RUSTOCK=$(jq -r '.builds["rustock-boton"]' "$C")
[ -f "$JAR" ] && [ -f "$RUSTOCK" ] || { echo "boton-live-slot: campaign $CID has no builds for Boton" >&2; exit 2; }
S=".scenarios.\"$SCEN\""
[ "$(cfg "$S")" != null ] || { echo "boton-live-slot: unknown scenario '$SCEN'" >&2; exit 2; }
OPT=$(cfg "$S.k6_option"); [ "$OPT" != null ] || { echo "boton-live-slot: scenario '$SCEN' has no k6_option" >&2; exit 2; }
DB=$(cfg "$S.db"); [ "$DB" = null ] && DB=empty
MIN="${CLIENTSLAB_ARM_MINUTES:-$(cfg .live.arm_minutes)}"; GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
HEAP=$(cfg .docker.jvm_heap); GPR=$(cfg .live.k6_gas_price); [ "$GPR" = null ] && GPR=node
PRIO=$(cfg .boton.box_priority); R=$(cfg .boton.remote_dir); GEN=$(basename "$(cfg .chain.genesis)")
K6="$LAB/$(cfg .mainnet_seed.k6)"; [ -x "$K6/infinite.sh" ] || { echo "boton-live-slot: no k6 suite at $K6" >&2; exit 2; }
REMOTE_HOME=/home/ubuntu; RR="$REMOTE_HOME/$R"
for o in "$OA" "$OB"; do mkdir -p "$o"; done
OA="$(cd "$OA" && pwd)"; OB="$(cd "$OB" && pwd)"
arm_name() { echo "$(basename "$(dirname "$1")")/$(basename "$1")"; }

# The seed on the box, per client, and what the node needs to run on a clone of it: the
# RSKj seed in perf-lab's layout, rustock's beside it (bin/boton-seed.sh); node.props
# (the seed's activations) and maxOpenFiles=1000 for RSKj as in Docker (bin/lib.sh db_setup).
START=0; MAINNET_PROPS=""; ARGS_KEY=live_args; EXPORT_KEY=export_args; RUSTOCK_DB="$RR/run/db"
RSKJ_SEED=/var/lib/rsk/mainnet-seed/seed/test/local-regtest/database; RUSTOCK_SEED=/var/lib/rsk/rustock-seed
if [ "$DB" = mainnet ]; then
  START=$(seed_tip); MAINNET_PROPS="-Ddatabase.rocksdb.maxOpenFiles=1000 $(cat "$(seed_dir)/node.props")"
  ARGS_KEY=mainnet_live_args; EXPORT_KEY=mainnet_export_args; RUSTOCK_DB=/var/lib/rsk/clientslab-db
fi
seed_of() { [ "$1" = rskj ] && echo "$RSKJ_SEED" || echo "$RUSTOCK_SEED"; }
seed_meta() { [ "$1" = rskj ] && echo "/var/lib/rsk/mainnet-seed/meta.json" || echo "/var/lib/rsk/rustock-seed.meta.json"; }
seed_ready() { [ "$1" = rskj ] && echo "/var/lib/rsk/mainnet-seed/READY" || echo "/var/lib/rsk/rustock-seed.READY"; }

# rustock's arguments with the box's paths, one per line (the remote script reads them
# back into an array). RPC bound to the box itself: k6 runs there.
SUBST="s#{datadir}#$RUSTOCK_DB#; s#{breakdown}#$RR/run/logs/block-breakdown.log#; s#{genesis}#$RR/conf/$GEN#; s#{flush}#$FLUSH#; s#{wallet}#$RR/conf/rustock-wallet.keys#; s#{coinbase}#$(cfg .live.mining_coinbase)#; s#{file}#$RR/run/export.txt#"
ARGS_DIR="$(dirname "$OA")"
jq -r ".$ARGS_KEY[]" "$LAB/clients/rustock.json" | sed -e "$SUBST" -e 's#^0\.0\.0\.0$#127.0.0.1#' > "$ARGS_DIR/.rustock-live.args"
jq -r ".$EXPORT_KEY[]" "$LAB/clients/rustock.json" | sed -e "$SUBST" > "$ARGS_DIR/.rustock-export.args"

lock_boxes() { box_lock A "$PRIO"; box_lock B "$PRIO"; }
unlock_boxes() { box_unlock B; box_unlock A; }
lock_boxes; trap unlock_boxes EXIT

upload() {
  local box="$1" client="$2" out="$3" h; h=$(box_host "$box")
  local rs=(rsync -a -e "ssh ${BOX_SSH[*]}")
  box_ssh "$box" "mkdir -p $R/bin $R/conf/rskj $R/run $R/k6-tests"
  "${rs[@]}" "$JAR" "ubuntu@$h:$R/bin/rsk.jar"
  "${rs[@]}" "$RUSTOCK" "ubuntu@$h:$R/bin/rustock-cli"
  "${rs[@]}" "$LAB/bin/boton-live-remote.sh" "ubuntu@$h:$R/bin/boton-live-remote.sh"
  "${rs[@]}" "$LAB/conf/rskj/" "ubuntu@$h:$R/conf/rskj/"
  "${rs[@]}" "$LAB/$(cfg .chain.genesis)" "ubuntu@$h:$R/conf/$GEN"
  "${rs[@]}" "$LAB/conf/rustock-wallet.keys" "ubuntu@$h:$R/conf/rustock-wallet.keys"
  "${rs[@]}" "$ARGS_DIR/.rustock-live.args" "ubuntu@$h:$R/rustock-live.args"
  "${rs[@]}" "$ARGS_DIR/.rustock-export.args" "ubuntu@$h:$R/rustock-export.args"
  "${rs[@]}" --delete --exclude node_modules --exclude .git --exclude results --exclude reports \
    "$K6/" "ubuntu@$h:$R/k6-tests/"
  cat > "$out/.arm.env" <<ENV
CLIENT=$client
ARTIFACT=$([ "$client" = rskj ] && echo "$JAR" || echo "$RUSTOCK")
SCEN=$SCEN
OPT=$OPT
MIN=$MIN
GAS=$GAS
FLUSH=$FLUSH
HEAP="$HEAP"
GEN=$GEN
GPR=$GPR
DB=$DB
START=$START
SEED=$([ "$DB" = mainnet ] && seed_of "$client")
MAINNET_PROPS="$MAINNET_PROPS"
ENV
  "${rs[@]}" "$out/.arm.env" "ubuntu@$h:$R/arm.env"
  # The suite's dependencies, installed once per upload of a new package-lock.json.
  box_ssh "$box" "set -e; chmod +x $R/bin/rustock-cli $R/bin/boton-live-remote.sh; $R/bin/rustock-cli --version >/dev/null
    cd $R/k6-tests && mkdir -p results && { [ node_modules/.installed -nt package-lock.json ] || { npm install --silent --no-audit --no-fund >/dev/null 2>&1 && touch node_modules/.installed; }; }"
  if [ "$DB" = mainnet ]; then
    # The box must hold this client's seed, the one this Mac's cross replays start from.
    local tip; tip=$(box_ssh "$box" "[ -e $(seed_ready "$client") ] && jq -r .seed_tip_hash $(seed_meta "$client")" || true)
    [ "$tip" = "$(jq -r .seed_tip_hash "$(seed_dir)/meta.json")" ] \
      || { echo "box $box has no $client seed ending at the lab's seed tip (bin/boton-seed.sh $box $client)"; return 1; }
  fi
}

# One arm on one box; the remote script's exit code is the arm's.
run_arm() {
  local box="$1" client="$2" out="$3" rc=0
  rm -rf "$out"; mkdir -p "$out"
  upload "$box" "$client" "$out" > "$out/upload.log" 2>&1 || { echo "upload to box $box failed" >> "$out/upload.log"; return 1; }
  box_quiesce "$box" || { echo "box $box still runs a node, load or replay" > "$out/remote.log"; return 1; }
  box_ssh "$box" "set -e; cd $R; sudo find run -mindepth 1 -delete; sudo rm -rf $RR/run/db $RR/run/db-trie /var/lib/rsk/clientslab-db; exec bash bin/boton-live-remote.sh" \
    > "$out/remote.log" 2>&1 || rc=$?
  rsync -a -e "ssh ${BOX_SSH[*]}" "ubuntu@$(box_host "$box"):$R/run/out/" "$out/" >> "$out/remote.log" 2>&1 || rc=1
  echo "box $box ($(box_host "$box"))" > "$out/host.txt"
  return $rc
}

log "boton live $SCEN: A $CA to $(arm_name "$OA"), B $CB to $(arm_name "$OB"), $DB database, $MIN min"
PA=""; PB=""
[ "$CA" = - ] || { run_arm A "$CA" "$OA" & PA=$!; }
[ "$CB" = - ] || { run_arm B "$CB" "$OB" & PB=$!; }
RA=0; RB=0
[ -z "$PA" ] || wait $PA || RA=$?
[ -z "$PB" ] || wait $PB || RB=$?
for box in A B; do
  rc=$([ $box = A ] && echo $RA || echo $RB); out=$([ $box = A ] && echo "$OA" || echo "$OB")
  [ "$rc" = 0 ] || log "boton live $SCEN box $box ($(arm_name "$out")) failed (exit $rc): $(tail -n 3 "$out/remote.log" 2>/dev/null | tr '\n' ' ')"
done
[ $RA = 0 ] && [ $RB = 0 ] || exit 1
summary() { [ "$1" = - ] && echo "skipped" || echo "$1 $(jq -r .blocks_mined "$2/arm.json") blocks"; }
log "boton live $SCEN: A $(summary "$CA" "$OA"), B $(summary "$CB" "$OB")"
