# Campaign 2026-10-27-c3: RSKj vs rustock

Mainnet DB on Boton, sequential design (docs/mainnet-db-plan.md): RSKj's cycles first on hard-link clones of the seed staged by perf-lab (/var/lib/rsk/mainnet-seed, tip #9,003,579), run as regtest with node.props, 2 CPUs and 7 GB RAM per box, JVM -Xms2G -Xmx4G, maxOpenFiles 1000. rustock's cycles come after the boxes' seed is swapped for rustock's compacted seed.

Status **done**, queued 2026-10-28T01:33:14Z, finished 2026-10-28T11:03:30Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `428086b40d4c` |

Each run replays the scenario's blocks into one client from a hard-link clone of the mainnet seed (`docs/mainnet-db-plan.md`) and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 10g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim@mainnet | boton | 94.2 | 98.0 | 1.05x slower | extend |
| ecdsa@mainnet | boton | 463.9 | 182.5 | 2.55x faster | rustock faster |

## mainnet-sim@mainnet, boton

**extend**: rustock faster in 1/6 cycles, median +4.65%, sign-test p=0.21875.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.05x slower | 1/6 | 0.219 | 1.02x faster, 1.08x slower, 1.04x slower, 1.07x slower, 1.05x slower, 1.03x slower |
| mean | 1.10x faster | 6/6 | 0.0312 | 1.19x faster, 1.07x faster, 1.07x faster, 1.10x faster, 1.10x faster, 1.10x faster |
| median | 1.12x slower | 0/6 | 0.0312 | 1.03x slower, 1.16x slower, 1.11x slower, 1.18x slower, 1.13x slower, 1.10x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 94.2 | 98.0 | 1.05x slower |
| executeMs | 43.4 | 86.2 | 1.99x slower (0/6) |
| initialValidationMs | 24.1 | 3.6 | 6.74x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.3 | 0.0 | 60.24x faster (6/6) |
| preambleMs | 0.8 | 0.0 | rustock 0 ms (5/5) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 4.2 | 4.2 | 1.09x slower (3/6) |
| statePersistMs | 12.9 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 5.3 | 2.5 | 2.11x faster (6/6) |
| trieSaveMs | n/a | 14.8 |  |
| txExecutionMs | 29.0 | n/a |  |

## ecdsa@mainnet, boton

**rustock faster**: rustock faster in 6/6 cycles, median -60.75%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.55x faster | 6/6 | 0.0312 | 2.57x faster, 2.55x faster, 2.54x faster, 2.55x faster, 2.55x faster, 2.53x faster |
| mean | 2.51x faster | 6/6 | 0.0312 | 2.53x faster, 2.51x faster, 2.51x faster, 2.50x faster, 2.52x faster, 2.48x faster |
| median | 2.51x faster | 6/6 | 0.0312 | 2.53x faster, 2.51x faster, 2.50x faster, 2.51x faster, 2.52x faster, 2.50x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 463.9 | 182.5 | 2.55x faster |
| executeMs | 444.4 | 181.5 | 2.46x faster (6/6) |
| initialValidationMs | 2.3 | 0.1 | 25.97x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.6 | 0.0 | rustock 0 ms (6/6) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 4.8 | 0.2 | 19.08x faster (6/6) |
| statePersistMs | 0.1 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 1.6 | 0.2 | 9.17x faster (6/6) |
| trieSaveMs | n/a | 0.3 |  |
| txExecutionMs | 443.5 | n/a |  |
