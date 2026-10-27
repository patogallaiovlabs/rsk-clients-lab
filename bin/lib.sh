# Shared helpers for bin/*.sh. Source it; do not run it.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE="$LAB/state"
mkdir -p "$STATE"/{builds,runs,logs,worktrees}

cfg() { jq -r "$1" "$LAB/config.json"; }
log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Homebrew's Python (the system one is 3.9) and the JDK RSKj targets.
[ -x /opt/homebrew/bin/python3 ] && export PATH="/opt/homebrew/bin:$PATH"
JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null || true)}"
export JAVA_HOME

# --- Machines: one node per machine, shared with rsk-perf-lab ----------------------------
# The locks live in ~/.research-lab/locks and follow rsk-perf-lab's bin/lib.sh protocol
# exactly (same directories, waiter files and priorities); change both together.
#   docker            this Mac's Docker VM. A campaign takes it as a `long` holder with its
#                     queue time as priority, so perf-lab's short replays and gates go first.
#   boton-A, boton-B  the Boton boxes, priority 2 (perf-lab's 6-boton is 0, its replays 1).
LOCKS="${RESEARCH_LAB_LOCKS:-$HOME/.research-lab/locks}"
LAB_NAME="clients-lab"
mkdir -p "$LOCKS"

lock_label() { echo "$LAB_NAME" > "$1/lab"; basename "$0" > "$1/what"; }
lock_drop() {
  local owner; owner=$(cat "$1/pid" 2>/dev/null || echo "")
  [ -z "$owner" ] || [ "$owner" = $$ ] || ! kill -0 "$owner" 2>/dev/null || return 0
  rm -rf "$1"
}

#   lock_acquire <name> [short|long[:<priority>]]
lock_acquire() {
  local name="$1" kind="${2:-short}" dir="$LOCKS/$1" wdir="$LOCKS/$1.waiting"
  local prio=""
  case "$kind" in long:*) prio="${kind#long:}"; kind=long ;; esac
  prio="${prio:-9999999999}"
  mkdir -p "$wdir"; touch "$wdir/$$.$kind.$prio"
  while true; do
    local w
    for w in "$wdir"/*; do
      [ -e "$w" ] || continue
      kill -0 "$(basename "$w" | cut -d. -f1)" 2>/dev/null || rm -f "$w"
    done
    local first; first=$(ls "$wdir" | grep '\.long\.' | sort -t. -k3,3n | head -1 || true)
    local overdue=""
    if [ -n "$first" ]; then
      local waited=$(( $(date +%s) - $(stat -f %m "$wdir/$first" 2>/dev/null || date +%s) ))
      [ "$waited" -gt $(( $(cfg .machines.long_lock_max_wait_min) * 60 )) ] && overdue=1
    fi
    if [ "$kind" = short ] && [ -n "$overdue" ]; then sleep 15; continue; fi
    if [ "$kind" = long ]; then
      if [ -n "$first" ] && [ "$first" != "$$.long.$prio" ]; then sleep 15; continue; fi
      if [ -z "$overdue" ] && ls "$wdir"/*.short* >/dev/null 2>&1; then sleep 15; continue; fi
    fi
    mkdir "$dir" 2>/dev/null && break
    local owner; owner=$(cat "$dir/pid" 2>/dev/null || echo "")
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      log "lock '$name': owner $owner is gone, taking it over"
      rm -rf "$dir"; continue
    fi
    sleep 15
  done
  rm -f "$wdir/$$.$kind.$prio"
  echo $$ > "$dir/pid"; lock_label "$dir"
}
lock_release() { lock_drop "$LOCKS/$1"; }

[ -f "$LAB/boton/hosts.env" ] && . "$LAB/boton/hosts.env"
BOTON_KEY="${BOTON_KEY:-$HOME/.ssh/rskj-automation}"
BOX_SSH=(-i "$BOTON_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=25 -o ServerAliveInterval=15)
box_host() { case "$1" in A) echo "$BOTON_HOST_A" ;; B) echo "$BOTON_HOST_B" ;; *) return 1 ;; esac; }
box_ssh() { local h; h=$(box_host "$1"); shift; ssh "${BOX_SSH[@]}" "ubuntu@$h" "$@"; }

#   box_lock <A|B> <prio>;  box_unlock <A|B>;  box_wanted <A|B> <my-prio>
box_lock() {
  local dir="$LOCKS/boton-$1" prio="$2"; local wdir="$dir.waiting"
  mkdir -p "$wdir"; touch "$wdir/$prio.$$"
  while true; do
    local w
    for w in "$wdir"/*; do
      [ -e "$w" ] || continue
      kill -0 "${w##*.}" 2>/dev/null || rm -f "$w"
    done
    local first; first=$(ls -tr "$wdir" | sort -s -t. -k1,1n | head -1 || true)
    if [ "$first" = "$prio.$$" ] && mkdir "$dir" 2>/dev/null; then break; fi
    local owner; owner=$(cat "$dir/pid" 2>/dev/null || echo "")
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      log "box $1: lock owner $owner is gone, taking it over"; rm -rf "$dir"; continue
    fi
    sleep 10
  done
  rm -f "$wdir/$prio.$$"
  echo $$ > "$dir/pid"; echo "$prio" > "$dir/prio"; lock_label "$dir"
}
box_unlock() { lock_drop "$LOCKS/boton-$1"; }
box_wanted() {
  ls "$LOCKS/boton-$1.waiting" 2>/dev/null | awk -F. -v p="$2" '$1 < p {f = 1} END {exit !f}'
}
# Before a run on a box: no node, no load, no replay of either lab.
box_quiesce() {
  box_ssh "$1" 'pkill -f "[i]nfinite.sh"; pkill -f "[k]6 run"; sudo systemctl stop rsk 2>/dev/null
    pkill -f "[C]onnectBlocks"; pkill -f "[r]ustock-cli"; for i in $(seq 1 60); do
      pgrep -f "[k]6 run|[i]nfinite.sh|[j]ava |[r]ustock-cli" >/dev/null || exit 0; sleep 1; done; exit 1'
}

# Space freed in the Docker Desktop VM goes back to macOS only after a trim.
trim_vm_disk() {
  docker run --rm --privileged --pid=host alpine nsenter -t 1 -m -- fstrim -a >/dev/null 2>&1 || true
}
wait_for_disk() {
  local min_gb; min_gb=$(cfg .machines.min_free_gb)
  trim_vm_disk
  while [ "$(df -k "$LAB" | awk 'NR==2{print int($4/1048576)}')" -lt "$min_gb" ]; do
    log "less than ${min_gb} GB free on the host disk; waiting"
    sleep 300; trim_vm_disk
  done
}
