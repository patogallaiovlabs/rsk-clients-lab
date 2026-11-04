#!/usr/bin/env bash
# One live slot on the Boton boxes: both boxes mine at the same time, one client each,
# natively and from an empty database, under the k6 suite running on each box. The Boton
# unit a live campaign repeats (docs/live-mining-plan.md, section 5):
#
#   bin/boton-live-slot.sh <campaign-id> <scenario> <slot-dir> <client-A> <client-B>
#   fwd slot: box A mines with RSKj, box B with rustock;  rev slot: swapped
#
# Takes both box locks at config.json boton.box_priority for the slot (another lab's more
# urgent work gets the boxes between slots), uploads the inputs once per box (rsync skips
# what did not change: the RSKj jar, the rustock binary, the lab's conf, the k6 suite with
# its npm install), then runs bin/boton-live-remote.sh on each box and copies its output
# back to <slot-dir>/{A,B}/ in the shape bin/live-arm.sh writes. The cross replay and the
# checks run on the Mac afterwards (bin/lab.py _boton_check). CLIENTSLAB_ARM_MINUTES
# overrides live.arm_minutes (smoke tests).
#
# Empty database only: the boxes hold no rustock seed beside the RSKj one (295 GB volume,
# 186 + 149 GB), so the @mainnet scenarios cannot be counterbalanced there.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CID="${1:?campaign id}"; SCEN="${2:?scenario}"; DIR="${3:?slot dir}"; CA="${4:?client on A}"; CB="${5:?client on B}"
C="$LAB/campaigns/$CID/campaign.json"
JAR=$(jq -r .builds.rskj "$C"); RUSTOCK=$(jq -r '.builds["rustock-boton"]' "$C")
[ -f "$JAR" ] && [ -f "$RUSTOCK" ] || { echo "boton-live-slot: campaign $CID has no builds for Boton" >&2; exit 2; }
S=".scenarios.\"$SCEN\""
[ "$(cfg "$S")" != null ] || { echo "boton-live-slot: unknown scenario '$SCEN'" >&2; exit 2; }
OPT=$(cfg "$S.k6_option"); [ "$OPT" != null ] || { echo "boton-live-slot: scenario '$SCEN' has no k6_option" >&2; exit 2; }
DB=$(cfg "$S.db"); [ "$DB" = null ] && DB=empty
[ "$DB" = empty ] || { echo "boton-live-slot: the boxes hold no rustock seed; only empty-database scenarios run live there" >&2; exit 2; }
MIN="${CLIENTSLAB_ARM_MINUTES:-$(cfg .live.arm_minutes)}"; GAS=$(cfg .chain.gas_limit); FLUSH=$(cfg .chain.flush_every_blocks)
HEAP=$(cfg .docker.jvm_heap); GPR=$(cfg .live.k6_gas_price); [ "$GPR" = null ] && GPR=node
PRIO=$(cfg .boton.box_priority); R=$(cfg .boton.remote_dir); GEN=$(basename "$(cfg .chain.genesis)")
K6="$LAB/$(cfg .mainnet_seed.k6)"; [ -x "$K6/infinite.sh" ] || { echo "boton-live-slot: no k6 suite at $K6" >&2; exit 2; }
REMOTE_HOME=/home/ubuntu; RR="$REMOTE_HOME/$R"
mkdir -p "$DIR"; DIR="$(cd "$DIR" && pwd)"

# rustock's arguments with the box's paths, one per line (the remote script reads them
# back into an array). RPC bound to the box itself: k6 runs there.
SUBST="s#{datadir}#$RR/run/db#; s#{breakdown}#$RR/run/logs/block-breakdown.log#; s#{genesis}#$RR/conf/$GEN#; s#{flush}#$FLUSH#; s#{wallet}#$RR/conf/rustock-wallet.keys#; s#{coinbase}#$(cfg .live.mining_coinbase)#; s#{file}#$RR/run/export.txt#"
jq -r '.live_args[]' "$LAB/clients/rustock.json" | sed -e "$SUBST" -e 's#^0\.0\.0\.0$#127.0.0.1#' > "$DIR/.rustock-live.args"
jq -r '.export_args[]' "$LAB/clients/rustock.json" | sed -e "$SUBST" > "$DIR/.rustock-export.args"

lock_boxes() { box_lock A "$PRIO"; box_lock B "$PRIO"; }
unlock_boxes() { box_unlock B; box_unlock A; }
lock_boxes; trap unlock_boxes EXIT

upload() {
  local box="$1" client="$2" h; h=$(box_host "$box")
  local rs=(rsync -a -e "ssh ${BOX_SSH[*]}")
  box_ssh "$box" "mkdir -p $R/bin $R/conf/rskj $R/run $R/k6-tests"
  "${rs[@]}" "$JAR" "ubuntu@$h:$R/bin/rsk.jar"
  "${rs[@]}" "$RUSTOCK" "ubuntu@$h:$R/bin/rustock-cli"
  "${rs[@]}" "$LAB/bin/boton-live-remote.sh" "ubuntu@$h:$R/bin/boton-live-remote.sh"
  "${rs[@]}" "$LAB/conf/rskj/" "ubuntu@$h:$R/conf/rskj/"
  "${rs[@]}" "$LAB/$(cfg .chain.genesis)" "ubuntu@$h:$R/conf/$GEN"
  "${rs[@]}" "$LAB/conf/rustock-wallet.keys" "ubuntu@$h:$R/conf/rustock-wallet.keys"
  "${rs[@]}" "$DIR/.rustock-live.args" "ubuntu@$h:$R/rustock-live.args"
  "${rs[@]}" "$DIR/.rustock-export.args" "ubuntu@$h:$R/rustock-export.args"
  "${rs[@]}" --delete --exclude node_modules --exclude .git --exclude results --exclude reports \
    "$K6/" "ubuntu@$h:$R/k6-tests/"
  cat > "$DIR/.$box.env" <<ENV
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
ENV
  "${rs[@]}" "$DIR/.$box.env" "ubuntu@$h:$R/arm.env"
  # The suite's dependencies, installed once per upload of a new package-lock.json.
  box_ssh "$box" "set -e; chmod +x $R/bin/rustock-cli $R/bin/boton-live-remote.sh; $R/bin/rustock-cli --version >/dev/null
    cd $R/k6-tests && mkdir -p results && { [ node_modules/.installed -nt package-lock.json ] || { npm install --silent --no-audit --no-fund >/dev/null 2>&1 && touch node_modules/.installed; }; }"
}

# One arm on one box; the remote script's exit code is the arm's.
run_arm() {
  local box="$1" client="$2" out="$3" rc=0
  rm -rf "$out"; mkdir -p "$out"
  upload "$box" "$client" > "$out/upload.log" 2>&1 || { echo "upload to box $box failed" >> "$out/upload.log"; return 1; }
  box_quiesce "$box" || { echo "box $box still runs a node, load or replay" > "$out/remote.log"; return 1; }
  box_ssh "$box" "set -e; cd $R; sudo find run -mindepth 1 -delete; sudo rm -rf $RR/run/db $RR/run/db-trie; exec bash bin/boton-live-remote.sh" \
    > "$out/remote.log" 2>&1 || rc=$?
  rsync -a -e "ssh ${BOX_SSH[*]}" "ubuntu@$(box_host "$box"):$R/run/out/" "$out/" >> "$out/remote.log" 2>&1 || rc=1
  echo "box $box ($(box_host "$box"))" > "$out/host.txt"
  return $rc
}

log "boton live $SCEN $(basename "$DIR"): A $CA, B $CB, $MIN min"
run_arm A "$CA" "$DIR/A" & PA=$!
run_arm B "$CB" "$DIR/B" & PB=$!
RA=0; RB=0; wait $PA || RA=$?; wait $PB || RB=$?
for box in A B; do
  rc=$([ $box = A ] && echo $RA || echo $RB)
  [ "$rc" = 0 ] || log "boton live $SCEN $(basename "$DIR") box $box failed (exit $rc): $(tail -n 3 "$DIR/$box/remote.log" 2>/dev/null | tr '\n' ' ')"
done
[ $RA = 0 ] && [ $RB = 0 ] || exit 1
log "boton live $SCEN $(basename "$DIR"): A $CA $(jq -r .blocks_mined "$DIR/A/arm.json") blocks, B $CB $(jq -r .blocks_mined "$DIR/B/arm.json") blocks"
