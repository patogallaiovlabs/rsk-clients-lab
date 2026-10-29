# Campaign 2026-10-29-c3: RSKj vs rustock, live mining

Live mining on the rebuilt mainnet seed, rerun of 2026-10-29-c2 with the k6 suite's ERC-20 bytecode recompiled (k6-tests 57c00ac; the old constant was odd-length and deployed no contract on RSKj, and rustock refused it): mainnet-sim under k6 option 14, the first measurement of the scenario with a working ERC-20; 30-minute arms, 10g memory, k6 pricing at the head minimum times 1.1 on both arms, rustock 1909b1c.

Status **failed**, queued 2026-10-29T21:13:09Z, finished 2026-10-29T22:18:29Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `1909b1c7ea16` |

## Stopped

```
live arm discarded, rerun the campaign to repeat the cycle: rustock mainnet-sim@mainnet c1-rustock: {'consensus_ok': False, 'kind': 'live', 'records': 115, 'expected': 115, 'first_difference': '', 'wall_s': 1949, 'client': 'rustock', 'artifact': 'clientslab-rustock:1909b1c7ea16-linux-arm64', 'start_height': 9003567, 'end_height': 9003682, 'checks': {'cross_replay': True, 'own_blocks': True, 'k6': True, 'qualifying': False}, 'own_siblings': 0, 'k6_success_pct': 100.0, 'k6_min_success_pct': 98.0, 'k6_metric': 'tx_success_rate', 'qualifying_blocks': 0, 'min_qualifying_blocks': 20, 'tx_count': 8972, 'gas_used': 1446085342, 'cross_replay': {'consensus_ok': True, 'records': 115, 'expected': 115, 'first_difference': '', 'wall_s': 38, 'client': 'rskj', 'artifact': '/Users/patricio/workspace/rsk/research-lab/rsk-clients-lab/state/builds/rskj-e507f45031cf0e8a71bf571fcdbfbe9aa529a21b.jar'}}
```

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).
