# Campaign 2026-10-26-c1: RSKj vs rustock

First campaign: RSKj perf-lab/integration vs rustock (Lerner fork + harness branches), Docker on this Mac.

Status **done**, queued 2026-10-27T00:52:29Z, finished 2026-10-27T04:07:04Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/harness` | `024e2032a6e1` |

Each run replays the scenario's blocks into one client from an empty database and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 6g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa | docker | 230.6 | 90.5 | 2.55x faster | rustock faster |
| mainnet-sim | docker | 17.8 | 56.1 | 3.21x slower | rustock slower |

## ecdsa, docker

**rustock faster**: rustock faster in 6/6 cycles, median -60.78%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.55x faster | 6/6 | 0.0312 | 2.55x faster, 2.55x faster, 2.60x faster, 2.51x faster, 2.57x faster, 2.50x faster |
| mean | 2.57x faster | 6/6 | 0.0312 | 2.58x faster, 2.55x faster, 2.61x faster, 2.51x faster, 2.59x faster, 2.51x faster |
| median | 2.54x faster | 6/6 | 0.0312 | 2.52x faster, 2.55x faster, 2.59x faster, 2.51x faster, 2.57x faster, 2.49x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 230.6 | 90.5 | 2.55x faster |
| executeMs | 229.0 | 90.3 | 2.54x faster (6/6) |
| initialValidationMs | 0.0 | 0.0 |  |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 0.1 |  |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.0 |  |
| txExecutionMs | 228.9 | n/a |  |

## mainnet-sim, docker

**rustock slower**: rustock faster in 0/6 cycles, median +220.76%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 3.21x slower | 0/6 | 0.0312 | 2.95x slower, 3.33x slower, 2.95x slower, 3.24x slower, 3.21x slower, 3.21x slower |
| mean | 2.98x slower | 0/6 | 0.0312 | 2.77x slower, 3.13x slower, 2.75x slower, 3.04x slower, 2.96x slower, 3.00x slower |
| median | 3.27x slower | 0/6 | 0.0312 | 3.08x slower, 3.43x slower, 3.11x slower, 3.35x slower, 3.28x slower, 3.27x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 17.8 | 56.1 | 3.21x slower |
| executeMs | 12.1 | 52.2 | 4.38x slower (0/6) |
| initialValidationMs | 2.8 | 1.3 | 2.21x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 | 185.19x faster (6/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 1.5 |  |
| statePersistMs | 2.4 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 1.1 | 61.54x slower (0/2) |
| txExecutionMs | 9.0 | n/a |  |
