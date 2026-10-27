---
name: run-campaign
description: Queue, run and read an RSKj vs rustock comparison campaign in rsk-clients-lab (scenarios mainnet-sim and ecdsa, in Docker on this Mac or on the Boton boxes). Use when asked to compare the clients, run a campaign, or report on one.
---
# Run a campaign

```bash
bin/lab.py queue --where docker --scenarios mainnet-sim,ecdsa     # prints <id>; --where docker,boton for both
nohup bin/lab.py run <id> > state/logs/<id>.log 2>&1 &             # or: bin/lab.py next
bin/lab.py status [<id>]
```

- Defaults: RSKj at `perf-lab/integration`, rustock at `clients-lab/comparison`, 6 cycles (up to
  12 while undecided). Override with `--rskj`, `--rustock`, `--cycles`, and say why in `--note`.
- A campaign waits for the shared machines (`.claude/rules/shared-machines.md`); a long wait
  behind perf-lab is normal. `ls ~/.research-lab/locks/*` shows holders and waiters.
- When it finishes: `campaigns/<id>/report.md` (facts). Then agent-analyst writes
  `analysis.md` and agent-writer `summary.md`.
- `status: consensus-failure`: hand it to agent-validator. `status: failed`: agent-diagnose;
  rerun `bin/lab.py run <id>` after a machine fault (finished cycles are kept).
