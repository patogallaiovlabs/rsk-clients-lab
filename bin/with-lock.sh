#!/usr/bin/env bash
# Run one command while holding this Mac's shared Docker slot (as a short holder), so a
# heavy build or a test replay never runs on top of a benchmark, this lab's or another's.
#
#   bin/with-lock.sh <command> [args...]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ $# -gt 0 ] || { echo "usage: with-lock.sh <command> [args...]" >&2; exit 2; }
lock_acquire docker
trap 'lock_release docker' EXIT
"$@"
