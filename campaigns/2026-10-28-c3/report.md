# Campaign 2026-10-28-c3: RSKj vs rustock, live mining

First full live mining campaign on the small chain: 30-minute arms, cycles per config, rustock cb6d948 (mined headers carry version 2 and ummRoot). Follows the smoke tests 2026-10-27-c4, 2026-10-28-c1 and c2, which validated the cross replay both ways.

Status **failed**, queued 2026-10-28T11:21:25Z, finished 2026-10-28T12:25:08Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `cb6d948` | `cb6d948e2d56` |

## Stopped

```
live arm discarded, rerun the campaign to repeat the cycle: rustock ecdsa c1-rustock: {'consensus_ok': False, 'kind': 'live', 'records': 129, 'expected': 123, 'first_difference': '> 124 c83c2a4bd17ba1761dfe5aea345d48161698710107275cb4d155434f8906c1bc', 'wall_s': 1949, 'client': 'rustock', 'artifact': 'clientslab-rustock:cb6d948e2d56-linux-arm64', 'start_height': 0, 'end_height': 123, 'checks': {'cross_replay': True, 'own_blocks': False, 'k6': False, 'qualifying': True}, 'k6_success_pct': 68.02, 'k6_min_success_pct': 80.0, 'k6_metric': 'stress_call_success_rate', 'qualifying_blocks': 70, 'min_qualifying_blocks': 20, 'tx_count': 9004, 'gas_used': 2604360426, 'cross_replay': {'consensus_ok': True, 'records': 123, 'expected': 123, 'first_difference': '', 'wall_s': 22, 'client': 'rskj', 'artifact': '/Users/patricio/workspace/rsk/research-lab/rsk-clients-lab/state/builds/rskj-e507f45031cf0e8a71bf571fcdbfbe9aa529a21b.jar'}}
```

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host.
