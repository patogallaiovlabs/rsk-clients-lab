#!/usr/bin/env bash
# Swap a Boton box's mainnet seed for rustock's (docs/mainnet-db-plan.md, sequential design):
# remove perf-lab's RSKj seed and its clones from the box's data volume, then copy the
# compacted rustock seed (Docker volume perflab-mainnet, /rustock-seed, about 148 GB) to
# /var/lib/rsk/rustock-seed. Afterwards perf-lab's 6-boton mainnet stage needs the RSKj seed
# uploaded again (rsk-perf-lab/bin/boton-seed-upload.sh) before it can run on that box.
#
#   bin/boton-rustock-seed.sh <A|B>
#   -> state/logs/rustock-seed-<box>.log; /var/lib/rsk/rustock-seed/, READY beside it
#
# The copy is rsync with --partial (resumable) under the box's lock at priority 2, as
# perf-lab's upload does; it hands the box over when a more urgent waiter appears.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOX="${1:?usage: boton-rustock-seed.sh <A|B>}"; H=$(box_host "$BOX")
VOL=$(cfg .mainnet_seed.volume); SRC=$(cfg .mainnet_seed.rustock_seed)
DEST=/var/lib/rsk/rustock-seed; CT="clientslab-seed-upload-$BOX"

if box_ssh "$BOX" "[ -e $DEST.READY ]"; then log "box $BOX already has the rustock seed"; exit 0; fi

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
box_quiesce "$BOX" || { log "box $BOX still runs a node or a replay"; exit 1; }
log "box $BOX: removing the RSKj seed and its clones ($(box_ssh "$BOX" 'df -h /var/lib/rsk | tail -1'))"
box_ssh "$BOX" "sudo rm -rf /var/lib/rsk/database /var/lib/rsk/mainnet-seed /var/lib/rsk/clientslab-db; sudo install -d -o ubuntu -g ubuntu $DEST"
log "box $BOX: $(box_ssh "$BOX" 'df -h /var/lib/rsk | tail -1')"
while true; do
  log "box $BOX: copying the rustock seed to $DEST"
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
box_ssh "$BOX" "sudo find $DEST -name '*.sst' -exec chmod a-w {} +; touch $DEST.READY; du -sh $DEST; df -h /var/lib/rsk | tail -1"
log "box $BOX: rustock seed ready in $DEST"
