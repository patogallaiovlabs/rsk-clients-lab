# Campaign 2026-10-27-c2: RSKj vs rustock

Mainnet DB on this Mac, sequential design (docs/mainnet-db-plan.md): RSKj's six cycles of each scenario ran first (21:41-21:51Z) on hard-link clones of perf-lab's mainnet seed (tip #9,003,579); then this Mac's RSKj seed was deleted, rustock's converted seed compacted and its index rebuilt (head #9,003,579 0x471f0ffc, same executed state root), and rustock's six cycles ran (22:08-22:11Z) on clones of it. Cycles are paired by number, not interleaved. Both clients run the seed as regtest (chain id 33, conf/genesis_25M.json, every hardfork active): RSKj with --regtest and node.props as in perf-lab, rustock with the small chain's flags on the single trie backend; the sample's transactions carry chain id 33. The samples were mined by RSKj on the seed under k6 (samples/*@mainnet/meta.json). Containers: 4 CPUs, 10g memory (docker.mainnet_memory). A first rustock attempt under --network-id 30 with the mainnet-overrides ladder diverged at the first block and was discarded; see the plan's night finding.

Status **done**, queued 2026-10-27T21:41:27Z, finished 2026-10-27T22:11:21Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `ecbacadcf1ed` |

Each run replays the scenario's blocks into one client from a hard-link clone of the mainnet seed (`docs/mainnet-db-plan.md`) and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 10g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim@mainnet | docker | 19.6 | 41.3 | 2.13x slower | rustock slower |
| ecdsa@mainnet | docker | 224.4 | 88.7 | 2.53x faster | rustock faster |

## mainnet-sim@mainnet, docker

**rustock slower**: rustock faster in 0/6 cycles, median +113.22%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.13x slower | 0/6 | 0.0312 | 2.02x slower, 2.02x slower, 2.15x slower, 2.19x slower, 2.12x slower, 2.15x slower |
| mean | 1.94x slower | 0/6 | 0.0312 | 1.84x slower, 1.77x slower, 1.94x slower, 1.98x slower, 1.95x slower, 1.93x slower |
| median | 2.23x slower | 0/6 | 0.0312 | 2.10x slower, 2.12x slower, 2.21x slower, 2.25x slower, 2.26x slower, 2.24x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 19.6 | 41.3 | 2.13x slower |
| executeMs | 12.2 | 36.9 | 3.05x slower (0/6) |
| initialValidationMs | 3.0 | 1.2 | 2.46x faster (6/6) |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.3 | 1.3 | 3.63x slower (0/6) |
| statePersistMs | 2.4 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.4 | 1.0 | 3.85x slower (0/6) |
| trieSaveMs | n/a | 6.7 |  |
| txExecutionMs | 9.1 | n/a |  |

## ecdsa@mainnet, docker

**rustock faster**: rustock faster in 6/6 cycles, median -60.40%, sign-test p=0.03125.

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.53x faster | 6/6 | 0.0312 | 2.53x faster, 2.57x faster, 2.50x faster, 2.52x faster, 2.54x faster, 2.52x faster |
| mean | 2.54x faster | 6/6 | 0.0312 | 2.54x faster, 2.62x faster, 2.51x faster, 2.53x faster, 2.55x faster, 2.53x faster |
| median | 2.52x faster | 6/6 | 0.0312 | 2.52x faster, 2.55x faster, 2.50x faster, 2.52x faster, 2.53x faster, 2.53x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 224.4 | 88.7 | 2.53x faster |
| executeMs | 221.5 | 88.3 | 2.51x faster (6/6) |
| initialValidationMs | 0.0 | 0.0 |  |
| onBestBlockMs | 0.0 | 0.0 |  |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.3 | 0.1 | 5.14x faster (6/6) |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.0 |  |
| trieSaveMs | n/a | 0.1 |  |
| txExecutionMs | 221.2 | n/a |  |
