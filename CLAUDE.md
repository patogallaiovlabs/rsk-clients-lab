# CLAUDE.md

rsk-clients-lab compares block processing time between RSKj (`perf-lab/integration`) and
rustock by replaying the same block samples into each. `README.md` explains the method and the
layout. It lives in the `research-lab` workspace next to `rsk-simulation` and `rsk-perf-lab`,
and depends on no other checkout at run time (`bin/import-sample.sh` reads rsk-perf-lab's
samples once, to create `samples/`).

Rules that matter:

- **One node per machine.** Anything heavy on this Mac (a replay, a release build, a Docker
  build) runs in the shared Docker slot: `bin/with-lock.sh <command>`, or `lock_acquire docker`
  in a script. Boton boxes: `box_lock A|B 2`. The locks in `~/.research-lab/locks` are shared
  with rsk-perf-lab and follow its `bin/lib.sh` protocol; change both together.
- **Correctness before speed.** No timing counts from a run whose hashes do not match
  `samples/<scenario>/reference_hashes.txt`.
- **Fairness.** Same blocks, machine, limits and fresh database for both clients; no tuning of
  one client only; every report lists both commits and every non-default setting.
- **Adapter boundary.** Changes in `clients/rustock` are harness-only (config, import, timing,
  packaging), on `harness/*` branches merged into `clients-lab/harness`. The lab builds
  `clients-lab/comparison`, which tracks that merge. Never a change to what the client
  computes or how fast.
- Never push. Commits only when the user asks. The user does not attend on weekends: decisions
  pending on Friday get a stated default.
- House style for prose: `.claude/skills/prose/SKILL.md`.
