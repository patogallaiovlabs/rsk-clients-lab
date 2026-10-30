# Campaign 2026-10-29-c1: RSKj vs rustock, live mining

Live mining on the rebuilt mainnet seed, rerun of 2026-10-28-c6 with k6 pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (live.k6_gas_price; rustock's eth_gasPrice answered the seed history's 26 M wei and its miner mined over the RSKIP252 cap): ecdsa under k6 option 7, 30-minute arms, 10g memory, rustock 1909b1c.

Status **done**, queued 2026-10-29T12:52:34Z, finished 2026-10-29T19:35:47Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `1909b1c7ea16` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa@mainnet | docker | 236.9 | 92.9 | 2.58x faster | rustock faster |

## ecdsa@mainnet, docker

**rustock faster**: rustock faster in 6/6 cycles, median -61.30%, sign-test p=0.03125.

| cycle | client | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|
| 1 | rskj | 110 | 62 | 11354 | 2,688,061,588 | 100.00% | ok | yes |
| 1 | rustock | 119 | 70 | 11274 | 2,778,522,881 | 100.00% | ok | yes |
| 2 | rskj | 115 | 67 | 10153 | 2,810,822,554 | 100.00% | ok | yes |
| 2 | rustock | 117 | 68 | 11303 | 2,732,105,875 | 100.00% | ok | yes |
| 3 | rskj | 122 | 74 | 11149 | 2,958,880,813 | 100.00% | ok | yes |
| 3 | rustock | 110 | 61 | 10135 | 2,539,061,070 | 100.00% | ok | yes |
| 4 | rskj | 129 | 81 | 11772 | 3,133,124,419 | 100.00% | ok | yes |
| 4 | rustock | 123 | 74 | 9859 | 2,845,336,109 | 100.00% | ok | yes |
| 5 | rskj | 138 | 90 | 14687 | 3,384,863,044 | 100.00% | ok | yes |
| 5 | rustock | 111 | 62 | 10366 | 2,589,628,751 | 100.00% | ok | yes |
| 6 | rskj | 116 | 68 | 11038 | 2,833,173,180 | 100.00% | ok | yes |
| 6 | rustock | 106 | 57 | 9378 | 2,444,544,012 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.58x faster | 6/6 | 0.0312 | 2.59x faster, 2.52x faster, 2.28x faster, 2.58x faster, 2.78x faster, 2.59x faster |
| mean | 2.18x faster | 6/6 | 0.0312 | 2.19x faster, 2.18x faster, 1.83x faster, 2.18x faster, 2.68x faster, 2.39x faster |
| median | 2.55x faster | 6/6 | 0.0312 | 2.49x faster, 2.50x faster, 2.52x faster, 2.75x faster, 2.79x faster, 2.58x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 236.9 | 92.9 | 2.58x faster |
| executeMs | 218.2 | 89.6 | 2.46x faster (6/6) |
| extendAlternativeChainMs | 1.2 | n/a |  |
| initialValidationMs | 7.3 | 0.2 | 36.36x faster (6/6) |
| onBestBlockMs | 0.1 | 0.2 | 1.57x slower (0/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 2.7 | 0.0 | 95.24x faster (6/6) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 3.8 | 1.2 | 3.15x faster (6/6) |
| statePersistMs | 0.1 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.8 | 0.6 | 1.40x faster (4/6) |
| trieSaveMs | n/a | 0.8 |  |
| txExecutionMs | 216.4 | n/a |  |
