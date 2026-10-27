---
name: update-client
description: Move a client in rsk-clients-lab to a new ref (a new perf-lab/integration head, a new rustock upstream release or merged adapter PRs) and re-run the correctness gate.
---
# Update a client

1. `git -C clients/<name> fetch --all` and pick the ref. RSKj: campaigns already take the
   current `perf-lab/integration` head at their start; update the submodule pointer only when the
   user asks for a commit. rustock: when upstream merged adapter PRs, rebase `clients-lab/harness`
   on upstream `main`, move `clients-lab/comparison` onto it, and drop the merged branches; when
   all merged, set `ref` in `clients/rustock.json` to `main`.
2. Build: `bin/build-client.sh <name> <ref> [platform]` (rustock release builds under
   `bin/with-lock.sh`).
3. Correctness: agent-validator replays every scenario. A new failure blocks the update.
4. Note the change (old and new commit, why) in the next campaign's `--note`.
