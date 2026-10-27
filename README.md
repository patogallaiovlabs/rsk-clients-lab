# rsk-clients-lab

Compares the block processing time of two RSK clients on the same workloads:

- **RSKj** at the head of `perf-lab/integration`, which carries every change rsk-perf-lab has proven;
- **rustock**, the same client written in Rust, from [SergioDemianLerner/rustock](https://github.com/SergioDemianLerner/rustock), a fork well ahead of [rustock-rs/rustock](https://github.com/rustock-rs/rustock).

The lab measures. It does not optimize either client.

## Method

Each campaign replays the same blocks into both clients, one client at a time, from an empty
database. The blocks were mined by RSKj under k6 load, so the workload is inside them and both
clients execute identical transactions:

| Scenario | Blocks | Workload |
|---|---|---|
| `mainnet-sim` | 1..1159 | k6 option 14: storage writes, ERC-20, native transfers and calldata-heavy rollup txs, about 164 txs per block |
| `ecdsa` | 1..207 | k6 option 7: signature-recovery-heavy contract calls |

RSKj replays with `ConnectBlocks`; rustock with `import-blocks`, which the harness adapter adds
(see "The rustock adapter"). Both log one line per block in RSKj's format,
`block connect breakdown best: block=… hash=… totalMs=… executeMs=… …`, so one analyzer reads
both. `docs/timing-scope.md` maps each client's phases and states what `totalMs` covers in each.

A run counts only if every block was imported with exactly RSKj's reference hashes. A mismatch
stops the campaign and is reported as a consensus finding about rustock.

A cycle is one run of each client, the order alternating between cycles. A campaign runs 6
cycles per scenario (up to 12 when the direction is consistent but not yet significant), and
judges with rsk-perf-lab's statistics: per run, the 10% trimmed mean of per-block `totalMs` over
the blocks at least 90% full, with the plain mean and median beside it; per cycle, the paired
difference; across cycles, the exact sign test. The verdict is "rustock faster", "rustock slower"
or "no difference", with the minimum difference set per scenario in `config.json`.

| Where | How |
|---|---|
| Docker, this Mac | each client in its own container with the same CPU and memory limits and a fresh data volume |
| Boton, boxes A and B | native binaries (RSKj jar, rustock built for linux/amd64 in Ubuntu 22.04), counterbalanced: one slot runs RSKj on A and rustock on B, the next swaps them |

One node per machine at a time. This Mac's Docker VM and the Boton boxes are shared with
rsk-perf-lab through the locks in `~/.research-lab/locks` (see `bin/lib.sh`).

Out of scope, because rustock cannot do it yet: live mining under k6 (it has no miner and no
wallet) and the mainnet database (it cannot read RSKj's).

## The rustock adapter

rustock needs small harness-only changes to be measured, each proposed upstream as a pull
request to the SergioDemianLerner fork from a branch in `clients/rustock`:

1. a regtest chain from a genesis file with RSKj's activation heights and REMASC constants;
2. `import-blocks --file`, through the same validation and execution path as sync;
3. the per-block timing line;
4. a multi-arch Dockerfile and the linux/amd64 build for Boton.

Until they merge, `clients-lab/harness` holds the merge of all four. The lab builds
`clients-lab/comparison`, which tracks that merge and holds comparison-only instrumentation.
Every report names the commit. No adapter change may touch what the client computes or how fast.

## Layout

| Path | What |
|---|---|
| `clients/rskj`, `clients/rustock` | submodules; `clients/<name>.json` describes how each is built and run |
| `conf/` | genesis and RSKj node config, the same files rsk-perf-lab uses |
| `samples/<scenario>/` | block file (gitignored), reference hashes, `meta.json` with its sha256 |
| `bin/` | `build-client.sh`, `replay-docker.sh`, `import-sample.sh`, `with-lock.sh`, stats and analyzer |
| `docs/` | timing scope, adapter pull request descriptions |
| `campaigns/<date>-<id>/` | a campaign's report (raw data under `raw/`, not committed) |
| `state/` | builds, runs, logs (gitignored) |

## Commands

```bash
bin/build-client.sh rskj perf-lab/integration             # -> state/builds/rskj-<sha>.jar
bin/build-client.sh rustock clients-lab/comparison linux-arm64
bin/replay-docker.sh rskj state/builds/rskj-<sha>.jar ecdsa state/runs/try-rskj
bin/with-lock.sh <command>                                # run anything heavy in the shared Docker slot
```
