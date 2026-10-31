# Campaign 2026-10-30-c3: RSKj vs rustock, live mining

mainnet-sim live on the mainnet seed, rerun of 2026-10-29-c3 with rustock 6712f28 (miner packs by gas used, RSKIP252 cap, eth_gasPrice gated on the fee market), gated by 2026-10-30-c1. k6 suite 57c00ac with the recompiled ERC-20 bytecode.

Status **done**, queued 2026-10-30T22:18:29Z, finished 2026-10-31T18:44:26Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `6712f28f987f` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 50 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim@mainnet | docker | 42.8 | 79.4 | 1.73x slower | rustock slower |

## mainnet-sim@mainnet, docker

**rustock slower**: rustock faster in 0/6 cycles, median +73.15%, sign-test p=0.03125.

| cycle | client | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|
| 1 | rskj | 135 | 87 | 22404 | 3,309,704,537 | 100.00% | ok | yes |
| 1 | rustock | 130 | 81 | 21724 | 3,199,216,015 | 99.99% | ok | yes |
| 2 | rskj | 123 | 75 | 19837 | 3,035,866,288 | 100.00% | ok | yes |
| 2 | rustock | 122 | 72 | 19955 | 2,995,581,608 | 99.99% | ok | yes |
| 3 | rskj | 125 | 77 | 20641 | 3,086,262,530 | 100.00% | ok | yes |
| 3 | rustock | 123 | 73 | 19935 | 3,021,134,405 | 100.00% | ok | yes |
| 4 | rskj | 115 | 67 | 18758 | 2,821,884,551 | 100.00% | ok | yes |
| 4 | rustock | 130 | 81 | 21605 | 3,169,974,749 | 100.00% | ok | yes |
| 5 | rskj | 147 | 99 | 23773 | 3,620,765,093 | 100.00% | ok | yes |
| 5 | rustock | 115 | 66 | 18549 | 2,826,753,462 | 100.00% | ok | yes |
| 6 | rskj | 120 | 72 | 19838 | 2,952,705,678 | 100.00% | ok | yes |
| 6 | rustock | 132 | 83 | 21679 | 3,215,358,997 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.73x slower | 0/6 | 0.0312 | 2.31x slower, 1.88x slower, 1.73x slower, 1.73x slower, 1.73x slower, 1.73x slower |
| mean | 1.77x slower | 0/6 | 0.0312 | 2.57x slower, 1.87x slower, 1.74x slower, 1.80x slower, 1.73x slower, 1.65x slower |
| median | 1.80x slower | 0/6 | 0.0312 | 2.35x slower, 2.03x slower, 1.70x slower, 1.79x slower, 1.81x slower, 1.78x slower |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 42.8 | 79.4 | 1.73x slower |
| executeMs | 20.6 | 67.9 | 3.23x slower (0/6) |
| initialValidationMs | 6.3 | 1.4 | 4.62x faster (6/6) |
| onBestBlockMs | 0.2 | 1.3 | 6.45x slower (0/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 2.0 | 0.3 | 7.28x faster (6/6) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 4.4 | 2.3 | 1.71x faster (6/6) |
| statePersistMs | 5.2 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 3.5 | 5.0 | 1.62x slower (1/6) |
| trieSaveMs | n/a | 12.2 |  |
| txExecutionMs | 14.4 | n/a |  |
