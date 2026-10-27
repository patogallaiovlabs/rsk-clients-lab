---
name: add-client
description: Onboard another RSK client into rsk-clients-lab, from submodule to a passing correctness replay.
---
# Add a client

1. `git submodule add <url> clients/<name>`; write `clients/<name>.json` (repo, ref, artifact,
   how to replay).
2. Check what the harness needs and the client lacks: the regtest chain from
   `conf/genesis_25M.json` with RSKj's activations (`conf/rskj/rsk.conf`), import of an
   ExportBlocks file from an empty database, the per-block line
   `block connect breakdown best: block=… hash=… totalMs=…` with `totalMs` covering the same work
   as RSKj's (`docs/timing-scope.md`), and a Linux build (arm64 for Docker, amd64 for Boton).
3. Missing pieces go to agent-adapter, harness-only (`.claude/rules/adapter-boundary.md`).
4. Teach `bin/build-client.sh`, `bin/replay-docker.sh` and `bin/boton-campaign.sh` the client,
   and extend `bin/stats.py` if it is compared against RSKj.
5. agent-validator replays every scenario; the client is in only when all pass.
6. Add its phases to `docs/timing-scope.md`.
