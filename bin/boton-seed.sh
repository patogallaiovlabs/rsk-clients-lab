#!/usr/bin/env bash
# Put one client's mainnet seed on a Boton box, removing the other client's seed and every
# clone (docs/mainnet-db-plan.md, sequential design: the box's 295 GB data volume holds one
# seed at a time, never both).
#
#   bin/boton-seed.sh <A|B> <rskj|rustock>
#   rskj:    /var/lib/rsk/mainnet-seed/{seed/,meta.json,READY}, perf-lab's layout, so its
#            Boton runs work on it again
#   rustock: /var/lib/rsk/rustock-seed/, with rustock-seed.meta.json and rustock-seed.READY
#            beside it
#
# The source is this Mac's seed volume (config.json mainnet_seed.volume): /seed (185 GB) or
# /rustock-seed (149 GB); rsync with --partial and --inplace, resumable, at about 5 MB/s
# per box over the shared uplink, so most of a day. Holds the box's lock at priority 2 and
# hands the box over, stopping rsync, when a more urgent waiter appears. A box that already
# has this seed (READY, and the seed tip hash of database-seed/seeds/mainnet/meta.json) is
# left alone. The meta.json copied beside either seed is this Mac's: rustock's seed was
# converted from the same RSKj seed, so both end at the same tip.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOX="${1:?usage: boton-seed.sh <A|B> <rskj|rustock>}"; CLIENT="${2:?usage: boton-seed.sh <A|B> <rskj|rustock>}"
H=$(box_host "$BOX"); VOL=$(cfg .mainnet_seed.volume); META="$(seed_dir)/meta.json"; TIP=$(jq -r .seed_tip_hash "$META")
case "$CLIENT" in
rskj)
  SRC=seed; DEST=/var/lib/rsk/mainnet-seed/seed; RMETA=/var/lib/rsk/mainnet-seed/meta.json; READY=/var/lib/rsk/mainnet-seed/READY
  OTHER="/var/lib/rsk/rustock-seed /var/lib/rsk/rustock-seed.READY /var/lib/rsk/rustock-seed.meta.json" ;;
rustock)
  SRC=$(cfg .mainnet_seed.rustock_seed); DEST=/var/lib/rsk/rustock-seed; RMETA=/var/lib/rsk/rustock-seed.meta.json; READY=/var/lib/rsk/rustock-seed.READY
  OTHER="/var/lib/rsk/mainnet-seed" ;;
*) echo "boton-seed: the client is rskj or rustock" >&2; exit 2 ;;
esac
CT="clientslab-seed-upload-$BOX"

if [ "$(box_ssh "$BOX" "[ -e $READY ] && jq -r .seed_tip_hash $RMETA" 2>/dev/null || true)" = "$TIP" ]; then
  log "box $BOX already has the $CLIENT seed ending at $TIP"; exit 0
fi

copy() {
  docker rm -f "$CT" >/dev/null 2>&1 || true
  docker run --rm --name "$CT" -v "$VOL":/v:ro -v "$BOTON_KEY":/k:ro alpine sh -c "
    apk add -q rsync openssh-client >/dev/null &&
    rsync -a --partial --inplace -z --compress-level=1 --info=progress2 --no-inc-recursive \
      -e 'ssh -i /k -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15' \
      /v/$SRC/ ubuntu@$H:$DEST/"
}

box_lock "$BOX" 2
trap 'docker rm -f "$CT" >/dev/null 2>&1 || true; box_unlock "$BOX"' EXIT
box_quiesce "$BOX" || { log "box $BOX still runs a node, load or replay"; exit 1; }
log "box $BOX: removing the other seed and every clone ($(box_ssh "$BOX" 'df -h /var/lib/rsk | tail -1'))"
box_ssh "$BOX" "rm -f $READY; sudo rm -rf /var/lib/rsk/database /var/lib/rsk/clientslab-db $OTHER
  sudo install -d -o ubuntu -g ubuntu $(dirname "$DEST") $DEST"
log "box $BOX: $(box_ssh "$BOX" 'df -h /var/lib/rsk | tail -1')"
while true; do
  log "box $BOX: copying the $CLIENT seed to $DEST"
  copy & PID=$!
  while kill -0 $PID 2>/dev/null; do
    sleep 60
    if box_wanted "$BOX" 2; then
      log "box $BOX wanted with a more urgent priority; pausing the copy"
      docker rm -f "$CT" >/dev/null 2>&1 || true; wait $PID || true
      box_unlock "$BOX"; box_lock "$BOX" 2
      log "box $BOX back; resuming the copy"
      continue 2
    fi
  done
  wait $PID && break
  log "box $BOX: rsync stopped; retrying in 5 minutes"; sleep 300
done
rsync -a -e "ssh ${BOX_SSH[*]}" "$META" "ubuntu@$H:$RMETA"
box_ssh "$BOX" "sudo find $DEST -name '*.sst' -exec chmod a-w {} +; touch $READY; du -sh $DEST; df -h /var/lib/rsk | tail -1"
log "box $BOX: $CLIENT seed ready in $DEST"
