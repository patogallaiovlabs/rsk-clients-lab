# Campaign 2026-10-27-c1: RSKj vs rustock

First Boton campaign: same builds as 2026-10-26-c1, native on boxes A and B, counterbalanced. Stopped after two ecdsa cycles on 2026-10-27, resumed the same day (cycles 1 and 2 kept).

Status **done**, queued 2026-10-27T12:24:23Z, finished 2026-10-27T18:05:40Z.

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
| ecdsa | boton | 443.1 | 178.8 | 2.49x faster | rustock faster |
| mainnet-sim | boton | 77.1 | 116.2 | 1.51x slower | rustock slower |

## ecdsa, boton

**rustock faster**: rustock faster in 6/6 cycles, median -59.76%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.49x faster | 6/6 | 0.0312 | 2.49x faster, 2.48x faster, 2.50x faster, 2.49x faster, 2.48x faster, 2.48x faster |
| mean | 2.53x faster | 6/6 | 0.0312 | 2.53x faster, 2.53x faster, 2.54x faster, 2.53x faster, 2.52x faster, 2.53x faster |
| median | 2.46x faster | 6/6 | 0.0312 | 2.46x faster, 2.46x faster, 2.46x faster, 2.45x faster, 2.45x faster, 2.46x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 443.1 | 178.8 | 2.49x faster |
| executeMs | 438.3 | 178.5 | 2.46x faster (6/6) |
| initialValidationMs | 1.8 | 0.1 | 30.86x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 0.2 |  |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.1 |  |
| txExecutionMs | 438.1 | n/a |  |

## mainnet-sim, boton

**rustock slower**: rustock faster in 0/6 cycles, median +50.58%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.51x slower | 0/6 | 0.0312 | 1.45x slower, 1.47x slower, 1.54x slower, 1.51x slower, 1.50x slower, 1.58x slower |
| mean | 1.41x slower | 0/6 | 0.0312 | 1.37x slower, 1.39x slower, 1.44x slower, 1.41x slower, 1.41x slower, 1.48x slower |
| median | 1.59x slower | 0/6 | 0.0312 | 1.53x slower, 1.56x slower, 1.64x slower, 1.60x slower, 1.59x slower, 1.67x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 77.1 | 116.2 | 1.51x slower |
| executeMs | 38.7 | 106.7 | 2.77x slower (0/6) |
| initialValidationMs | 24.9 | 3.1 | 8.04x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 | 41.15x faster (6/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.2 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.8 | 3.9 | 5.15x slower (0/6) |
| statePersistMs | 11.1 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 2.7 | 2.2 | 1.21x faster (6/6) |
| txExecutionMs | 26.1 | n/a |  |
