# Campaign 2026-10-28-c4: RSKj vs rustock, live mining

Full live mining campaign on the small chain, rerun of 2026-10-28-c3 with rustock 1909b1c (--account-slots 500, as RSKj's accountSlots) and evm_stopMining before the arm's export; 30-minute arms, 6 cycles.

Status **done**, queued 2026-10-28T12:33:46Z, finished 2026-10-28T18:58:31Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `1909b1c` | `1909b1c7ea16` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa | docker | 227.3 | 78.1 | 2.94x faster | rustock faster |

## ecdsa, docker

**rustock faster**: rustock faster in 6/6 cycles, median -65.97%, sign-test p=0.03125.

| cycle | client | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|
| 1 | rskj | 122 | 104 | 11471 | 2,983,623,078 | 100.00% | ok | yes |
| 1 | rustock | 130 | 111 | 12970 | 2,949,532,378 | 100.00% | ok | yes |
| 2 | rskj | 140 | 121 | 13153 | 3,419,528,499 | 100.00% | ok | yes |
| 2 | rustock | 115 | 96 | 10945 | 2,639,645,194 | 100.00% | ok | yes |
| 3 | rskj | 126 | 107 | 13394 | 3,069,888,510 | 99.99% | ok | yes |
| 3 | rustock | 107 | 88 | 9768 | 2,470,880,243 | 100.00% | ok | yes |
| 4 | rskj | 139 | 121 | 15100 | 3,406,727,302 | 100.00% | ok | yes |
| 4 | rustock | 117 | 98 | 10709 | 2,731,485,280 | 100.00% | ok | yes |
| 5 | rskj | 120 | 102 | 11454 | 2,909,516,340 | 100.00% | ok | yes |
| 5 | rustock | 124 | 104 | 11118 | 2,890,762,921 | 100.00% | ok | yes |
| 6 | rskj | 126 | 108 | 14422 | 3,084,288,978 | 100.00% | ok | yes |
| 6 | rustock | 138 | 119 | 11835 | 3,202,292,992 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 2.94x faster | 6/6 | 0.0312 | 3.08x faster, 3.05x faster, 2.69x faster, 2.80x faster, 2.97x faster, 2.91x faster |
| mean | 2.94x faster | 6/6 | 0.0312 | 3.07x faster, 3.03x faster, 2.70x faster, 2.79x faster, 2.96x faster, 2.92x faster |
| median | 2.94x faster | 6/6 | 0.0312 | 3.05x faster, 3.07x faster, 2.69x faster, 2.77x faster, 2.96x faster, 2.91x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 227.3 | 78.1 | 2.94x faster |
| executeMs | 218.1 | 77.5 | 2.83x faster (6/6) |
| extendAlternativeChainMs | 0.0 | n/a |  |
| initialValidationMs | 6.8 | 0.1 | 54.64x faster (6/6) |
| onBestBlockMs | 0.0 | 0.1 | 1.67x slower (0/5) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.0 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.0 | 0.3 |  |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.1 |  |
| trieSaveMs | n/a | 0.1 |  |
| txExecutionMs | 216.2 | n/a |  |
