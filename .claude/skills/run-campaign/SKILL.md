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

- Defaults: RSKj at the ref in `clients/rskj.json`, rustock at `clients-lab/comparison`, 6 cycles (up to
  12 while undecided). Override with `--rskj`, `--rustock`, `--cycles`, and say why in `--note`.
- `--kind live`: live mining instead of replay (README "Live mining"). Docker only; each cycle is
  one 30-minute arm per client plus the cross replays, so count on 80 minutes per cycle on the
  small chain and more on the mainnet seed (`--scenarios mainnet-sim@mainnet,ecdsa@mainnet`).
  Needs the rustock adapter's live flags (`clients/rustock.json` `live_args`) and the k6 suite at
  `config.json` `mainnet_seed.k6`. A `status: failed` saying "live arm discarded" is an arm that
  measured nothing (few full blocks, k6 rejected); rerun `bin/lab.py run <id>` to repeat the cycle.
- A campaign waits for the shared machines (`.claude/rules/shared-machines.md`); a long wait
  behind another lab is normal. `ls ~/.research-lab/locks/*` shows holders and waiters.
- When it finishes: `campaigns/<id>/report.md` (facts). Then agent-analyst writes
  `analysis.md` and agent-writer `summary.md`.
- `status: consensus-failure`: hand it to agent-validator. `status: failed`: agent-diagnose;
  rerun `bin/lab.py run <id>` after a machine fault (finished cycles are kept).
