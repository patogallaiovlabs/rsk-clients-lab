#!/usr/bin/env bash
# Run queued campaigns one after another, detached, until the queue is empty.
# Does nothing if a worker is already running.
#
#   bin/start.sh
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PID="$STATE/worker.pid"
if [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "worker already running (pid $(cat "$PID"))"; exit 0
fi
nohup bash -c "
  echo \$\$ > '$PID'
  while ls '$STATE/queue/'* >/dev/null 2>&1; do python3 '$LAB/bin/lab.py' next; done
  rm -f '$PID'" >> "$STATE/logs/worker.log" 2>&1 &
echo "worker started; log: state/logs/worker.log"
