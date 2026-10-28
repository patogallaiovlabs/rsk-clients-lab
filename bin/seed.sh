#!/usr/bin/env bash
# The mainnet seed tooling (database-seed/, rsk-database-seed) with this lab's inputs: its
# node config and genesis, its k6 suite, its runtime image, its volume and its Docker lock.
#
#   bin/seed.sh extract <database.tar.gz>   # the mainnet database into the volume's /seed
#   bin/seed.sh bootstrap                   # fund the k6 senders, ramp to 25M gas, freeze
#   bin/seed.sh settle | verify [min]       # as prepare.sh documents them
#   bin/seed.sh clone <name>                # a hard-link clone at /<name> in the volume
#
# prepare.sh and clone.sh read every input from the environment (database-seed/lib.sh); the
# variable it takes the lock library from is named for the lab it was first written in.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TOOLING="$LAB/$(cfg .mainnet_seed.seed_tooling)"
export SEED=mainnet SEED_VOLUME="$(cfg .mainnet_seed.volume)" RUNTIME_IMAGE="$(cfg .mainnet_seed.runtime_image)"
export SIM_ROOT="$LAB" RSK_CONF="$LAB/conf/rskj/rsk.conf" GENESIS_DIR="$LAB/conf" LOGBACK="$LAB/conf/rskj/logback.xml"
export K6_DIR="$LAB/$(cfg .mainnet_seed.k6)" RSKJ="$LAB/clients/rskj" PERF_LAB_LIB="$LAB/bin/lib.sh"
case "${1:-}" in
  clone) shift; exec "$TOOLING/clone.sh" "$@" ;;
  extract|bootstrap|settle|verify) exec "$TOOLING/prepare.sh" "$@" ;;
  *) echo "usage: seed.sh extract <tar.gz> | bootstrap | settle | verify [min] | clone <name>" >&2; exit 2 ;;
esac
