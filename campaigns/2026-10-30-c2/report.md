# Campaign 2026-10-30-c2: RSKj vs rustock

RSKj baseline on upstream libsecp256k1 0.8.0: same RSKj commit e507f45 as 2026-10-30-c1, rebuilt against the repackaged co.rsk:native 1.4.0-SNAPSHOT (rsk-simulation/repos/native branch secp256k1-upstream-0.8.0, ae5cb38) in place of the 2019 fork of libsecp256k1 0.1. Single back-to-back replay measured 232.3 -> 96.6 ms/block; this campaign re-establishes the ecdsa row of the results table. Compare against 2026-10-30-c1 (RSKj 242.1, rustock 89.5).

Status **done**, queued 2026-10-30T20:48:18Z, finished 2026-10-30T20:55:05Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `71d3de24fa58` |

Each run replays the scenario's blocks into one client from an empty database and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 6g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa | docker | 94.9 | 89.2 | 1.07x faster | rustock faster |

## ecdsa, docker

**rustock faster**: rustock faster in 6/6 cycles, median -6.58%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.07x faster | 6/6 | 0.0312 | 1.07x faster, 1.08x faster, 1.07x faster, 1.07x faster, 1.02x faster, 1.08x faster |
| mean | 1.08x faster | 6/6 | 0.0312 | 1.08x faster, 1.09x faster, 1.07x faster, 1.08x faster, 1.03x faster, 1.09x faster |
| median | 1.06x faster | 6/6 | 0.0312 | 1.06x faster, 1.07x faster, 1.06x faster, 1.06x faster, 1.02x faster, 1.07x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 94.9 | 89.2 | 1.07x faster |
| executeMs | 93.6 | 89.1 | 1.06x faster (6/6) |
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
| txExecutionMs | 93.4 | n/a |  |
