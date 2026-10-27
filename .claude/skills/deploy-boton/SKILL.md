---
name: deploy-boton
description: Deploy an RSKj build to a Boton instance (the rented Hetzner cloud VMs, ubuntu@<ip>) and run a k6 stress experiment on it. Use when asked to run a build, benchmark, stress test or A/B comparison "on Boton", "on a boton instance", "on the cloud node" or "on the remote box", or to check, collect or restore a run already on one.
---

# Run an experiment on a Boton instance

> Copied from rsk-simulation. Its `scripts/boton/...` paths live in `../rsk-simulation` (or
> rsk-perf-lab's `scripts/boton/`). In this lab, replays on the boxes run through
> `bin/boton-campaign.sh`; use this skill only for box setup and live k6 experiments, and take
> `box_lock <A|B> 2` (`bin/lib.sh`) for the whole time you use a box.

Full detail: `docs/boton-deployment.md`. This file is the procedure; read the doc before
executing anything non-obvious.

**Boton boxes do not run Docker.** They have the packaged RSKj systemd layout — a fat jar at
`/usr/share/rsk/rsk.jar` driven by `/etc/sysconfig/rsk`. Deploying = replace the jar and
config, restart. Never edit the unit file.

## Settle these before touching a box

1. **Which box, and is it free?** These boxes are often mid-sync on mainnet. Deploying stops
   that service and `deploy-node.sh` **wipes the database** — on a mainnet box that is days
   of resync. Check `systemctl is-active rsk` and what `RSKJ_OPTS` says, and **ask before
   taking a box that is doing something**.
2. **Which build(s)?** A git ref per box. For an A/B, deploy both from the same toolchain in
   one session.
3. **Isolated or peered?** Default to isolated, one experiment per box. Peering needs Hetzner
   firewall rules (doc, last section) — you cannot grant them from the box.

## Sequence

```bash
scripts/boton/build-jar.sh <ref> /tmp/rsk-<label>.jar    # local, ~20s, no Docker
scripts/boton/deploy-node.sh <host> <miner-id> /tmp/rsk-<label>.jar
scripts/boton/run-load.sh <host> 14                      # k6 runs ON the box
scripts/boton/collect.sh <host> <label>
python3 nmt/analyze_block_breakdown.py --label tip --baseline results/boton/baseline_summary.json \
        results/boton/tip/block-breakdown.log*
```

Use `<miner-id>` 1 and 2 for a pair — it selects the deterministic peer key, coinbase and
peer port matching the local docker miners.

## Verify, don't assume

- **The right jar is live:** `sudo grep -m1 git.hash /var/log/rsk/stress/rsk.log` — a failed
  start silently leaves the old jar running.
- **Blocks are full:** `gasUsed/gasLimit` ≈ 98–99 % on recent blocks. A started k6 is not a
  loaded node.
- **Both boxes are the same hardware** before comparing: `grep -m1 "model name" /proc/cpuinfo`.
- **The breakdown log is growing** — `/var/log/rsk/stress/block-breakdown.log`. No lines there
  means no metrics at the end of the run.

## Things that mislead

- **A slow node looks like a hung k6.** The scenario's `setup()` waits on receipts, so slow
  mining leaves k6 in `setup()` at near-zero load. Check block height before debugging k6.
- **Only port 22 is open**, and only from the user's network — no host firewall is involved,
  so there is nothing on the box to fix. k6 therefore runs on the box; from a laptop the
  ~175 ms RTT would cap throughput below what fills a block.
- **Never compare Boton numbers to laptop numbers.** Different cores, and k6 shares the box's
  2 cores with the node. Boton compares to Boton.
- **`infinite.sh` never exits.** Always `setsid nohup` it (`run-load.sh` does), and decide a
  fixed window — option 14's stage is 1 hour.
- **zsh does not word-split** unquoted option strings, so an ad-hoc `ssh $OPTS host` fails
  with a confusing "identity file not accessible". The repo scripts are bash and unaffected.

## Finishing

Restore the box from its `.bak-<stamp>` jar and sysconfig when the experiment ends, and say
what state you left it in — especially if you wiped a mainnet database.
