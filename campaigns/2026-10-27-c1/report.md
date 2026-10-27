# Campaign 2026-10-27-c1: RSKj vs rustock

First Boton campaign: same builds as 2026-10-26-c1, native on boxes A and B, counterbalanced. ecdsa, two complete cycles.

Status **done**, queued 2026-10-27T12:24:23Z, finished 2026-10-27T13:47:57Z.

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
| ecdsa | boton | 443.3 | 178.8 | 2.49x faster | extend |

## ecdsa, boton

**extend**: rustock faster in 2/2 cycles, median -59.78%, sign-test p=0.5.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.49x faster | 2/2 | 0.5 | 2.49x faster, 2.48x faster |
| mean | 2.53x faster | 2/2 | 0.5 | 2.53x faster, 2.53x faster |
| median | 2.46x faster | 2/2 | 0.5 | 2.46x faster, 2.46x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 443.3 | 178.8 | 2.49x faster |
| executeMs | 438.5 | 178.5 | 2.46x faster (2/2) |
| initialValidationMs | 1.8 | 0.1 | 31.06x faster (2/2) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 0.2 |  |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.1 |  |
| txExecutionMs | 438.3 | n/a |  |
