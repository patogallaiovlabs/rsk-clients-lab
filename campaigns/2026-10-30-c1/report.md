# Campaign 2026-10-30-c1: RSKj vs rustock

Correctness gate for rustock 6712f28: clients-lab/comparison fast-forwarded to fix/miner-gas-packing-cap-and-gasprice-gate (pack by gas used, RSKIP252 cap, eth_gasPrice fee-market gate). Previous ref 1909b1c. These are client fixes written for upstream, carried here until upstream merges them.

Status **done**, queued 2026-10-30T19:12:24Z, finished 2026-10-30T19:45:18Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `6712f28f987f` |

Each run replays the scenario's blocks into one client from an empty database and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 6g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim | docker | 18.5 | 57.3 | 3.10x slower | rustock slower |
| ecdsa | docker | 242.1 | 89.5 | 2.64x faster | rustock faster |

## mainnet-sim, docker

**rustock slower**: rustock faster in 0/6 cycles, median +209.61%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 3.10x slower | 0/6 | 0.0312 | 3.12x slower, 3.12x slower, 3.07x slower, 3.00x slower, 3.03x slower, 3.18x slower |
| mean | 2.82x slower | 0/6 | 0.0312 | 2.85x slower, 2.83x slower, 2.82x slower, 2.75x slower, 2.75x slower, 2.90x slower |
| median | 3.24x slower | 0/6 | 0.0312 | 3.24x slower, 3.38x slower, 3.22x slower, 3.24x slower, 3.18x slower, 3.29x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 18.5 | 57.3 | 3.10x slower |
| executeMs | 12.3 | 53.1 | 4.32x slower (0/6) |
| initialValidationMs | 2.9 | 1.3 | 2.25x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 | 112.36x faster (6/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 1.6 |  |
| statePersistMs | 2.4 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.1 | 1.2 | 11.20x slower (0/6) |
| trieSaveMs | n/a | 9.3 |  |
| txExecutionMs | 9.2 | n/a |  |

## ecdsa, docker

**rustock faster**: rustock faster in 6/6 cycles, median -62.09%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.64x faster | 6/6 | 0.0312 | 2.83x faster, 2.60x faster, 2.59x faster, 2.58x faster, 2.68x faster, 2.95x faster |
| mean | 2.70x faster | 6/6 | 0.0312 | 2.81x faster, 2.60x faster, 2.60x faster, 2.59x faster, 2.85x faster, 2.94x faster |
| median | 2.60x faster | 6/6 | 0.0312 | 2.98x faster, 2.60x faster, 2.58x faster, 2.57x faster, 2.60x faster, 3.10x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 242.1 | 89.5 | 2.64x faster |
| executeMs | 240.1 | 89.4 | 2.62x faster (6/6) |
| initialValidationMs | 0.0 | 0.0 | 2.38x slower (0/1) |
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
| txExecutionMs | 240.0 | n/a |  |
