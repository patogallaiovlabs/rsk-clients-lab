# Campaign 2026-10-28-c2: RSKj vs rustock, live mining

Live mining smoke test, third attempt: rustock cb6d948 (mined headers carry ummRoot on regtest); one cycle, 10-minute arms (CLIENTSLAB_ARM_MINUTES=10), small chain.

Status **failed**, queued 2026-10-28T10:54:31Z, finished 2026-10-28T11:20:36Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `cb6d948` | `cb6d948e2d56` |

## Stopped

```
live arm discarded, rerun the campaign to repeat the cycle: rskj ecdsa c1-rskj: {'consensus_ok': False, 'kind': 'live', 'records': 37, 'expected': 37, 'first_difference': '', 'wall_s': 633, 'client': 'rskj', 'artifact': '/Users/patricio/workspace/rsk/research-lab/rsk-clients-lab/state/builds/rskj-e507f45031cf0e8a71bf571fcdbfbe9aa529a21b.jar', 'start_height': 0, 'end_height': 37, 'checks': {'cross_replay': True, 'own_blocks': True, 'k6': True, 'qualifying': False}, 'k6_success_pct': 100.0, 'k6_min_success_pct': 80.0, 'k6_metric': 'stress_call_success_rate', 'qualifying_blocks': 17, 'min_qualifying_blocks': 20, 'tx_count': 3250, 'gas_used': 783069423, 'cross_replay': {'consensus_ok': True, 'records': 37, 'expected': 37, 'first_difference': '', 'wall_s': 2, 'client': 'rustock', 'artifact': 'clientslab-rustock:cb6d948e2d56-linux-arm64'}}
```

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host.
