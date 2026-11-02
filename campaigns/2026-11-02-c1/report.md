# Campaign 2026-11-02-c1: RSKj vs rustock

Correctness gate for rustock 2f185c8 (clients-lab/comparison: the miner fixes after 6712f28, written by another agent) and first replay of the re-mined mainnet-sim sample (970 blocks, k6 suite with the recompiled ERC20_BYTECODE, mined with RSKj fa5733f8eb9a9b733fa55c6b6326c1bf01e50a93). RSKj at perf-lab/integration with s010 landed (co.rsk:native 1.5.0-SNAPSHOT, libsecp256k1 0.8.0). One cycle: a gate, not a measurement.

Status **done**, queued 2026-11-02T21:29:33Z, finished 2026-11-02T21:42:29Z.

| client | ref | commit |
|---|---|---|
| RSKj | `fa5733f8eb9a9b733fa55c6b6326c1bf01e50a93` | `fa5733f8eb9a` |
| rustock | `2f185c8` | `2f185c8fe781` |

Each run replays the scenario's blocks into one client from an empty database and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 6g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim | docker | 17.4 | 56.3 | 3.25x slower | rustock slower |
| ecdsa | docker | 95.8 | 89.3 | 1.08x faster | rustock faster |

## mainnet-sim, docker

**rustock slower**: rustock faster in 0/6 cycles, median +225.18%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 3.25x slower | 0/6 | 0.0312 | 3.05x slower, 3.11x slower, 3.30x slower, 3.20x slower, 3.37x slower, 3.36x slower |
| mean | 2.99x slower | 0/6 | 0.0312 | 2.66x slower, 2.76x slower, 3.04x slower, 2.93x slower, 3.06x slower, 3.11x slower |
| median | 3.41x slower | 0/6 | 0.0312 | 3.29x slower, 3.24x slower, 3.51x slower, 3.31x slower, 3.58x slower, 3.57x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 17.4 | 56.3 | 3.25x slower |
| executeMs | 12.4 | 52.3 | 4.24x slower (0/6) |
| initialValidationMs | 1.8 | 1.2 | 1.43x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 1.5 | 31.10x slower (0/1) |
| statePersistMs | 2.4 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.1 | 1.1 | 14.24x slower (0/6) |
| trieSaveMs | n/a | 9.0 |  |
| txExecutionMs | 9.4 | n/a |  |

## ecdsa, docker

**rustock faster**: rustock faster in 6/6 cycles, median -7.29%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.08x faster | 6/6 | 0.0312 | 1.07x faster, 1.09x faster, 1.08x faster, 1.03x faster, 1.09x faster, 1.08x faster |
| mean | 1.09x faster | 6/6 | 0.0312 | 1.07x faster, 1.10x faster, 1.08x faster, 1.04x faster, 1.10x faster, 1.09x faster |
| median | 1.07x faster | 6/6 | 0.0312 | 1.07x faster, 1.07x faster, 1.07x faster, 1.03x faster, 1.07x faster, 1.08x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 95.8 | 89.3 | 1.08x faster |
| executeMs | 94.4 | 89.2 | 1.06x faster (6/6) |
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
| trieSaveMs | n/a | 0.1 |  |
| txExecutionMs | 94.2 | n/a |  |
