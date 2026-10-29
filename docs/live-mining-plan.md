# Plan: live mining under k6 load, RSKj vs rustock

Status: built and in use since 2026-10-28. Sections 1 to 6 are the design as proposed on
2026-10-27, read in the code at rustock `clients-lab/comparison` (8eb2285, on Lerner's
43dc5e5), RSKj's integration branch, the k6 suite (`k6-tests/`) and the live scripts that
preceded the lab's; where a claim is an inference rather than something read, the text says
so. The sections after them record what the runs found, latest last. What the design
settled on: the adapter branches `harness/timed-mining`, `harness/mined-block-timing`,
`harness/export-blocks`, `harness/mined-header-version` and `harness/account-slots`, all on
`clients-lab/harness`; 2 CPUs per container; no Boton live slot; and, since 2026-10-29, k6
pricing by the head minimum times 1.1 on both arms rather than by each node's `eth_gasPrice`.

The replay campaigns feed both clients the same blocks. A live campaign has each client mine
its own blocks under the same k6 load, as RSKj's own live A/B benchmarks do. The statistic
stays the same: per arm, the 10%
trimmed mean of `totalMs` over blocks at least 90% full, paired cycles, exact sign test.

## 1. Can k6 drive rustock today?

Mostly, through the node's own wallet. Neither scenario signs locally:
`utils/transaction-signer.js` says so at `createRawTransaction` (a placeholder) and every
send is `eth_sendTransaction` with an unlocked account. Both scenarios read the account list
from `eth_accounts` in `setup()` and take one account per VU (10 VUs each).

What options 14 and 7 call, and what the fork answers (`crates/rpc/src/server.rs`):

| Method | Used for | rustock |
|---|---|---|
| `eth_accounts` | the sender list | `sign::eth_accounts`, the wallet's addresses; empty without `--wallet-file` |
| `eth_sendTransaction` | every transaction, with `from`, `nonce`, `gas`, `gasPrice`, `data` set by k6 | `sign::eth_send_transaction`: signs with the wallet key, chain id from the chain config, then the pool |
| `eth_getTransactionCount` `pending` and `latest` | the in-flight gate, every iteration | `state::eth_get_transaction_count`; `pending` reads the pool's pending nonce |
| `eth_gasPrice` | the price of every transaction | `eth::eth_gas_price`, from the gas price tracker |
| `eth_estimateGas` | contract deployments in `setup()` (capped) | `call::eth_estimate_gas` |
| `eth_getBlockByNumber` `latest` | block gas limit for pacing and phase sizing | present; block 0 was invisible until #332 fixed it |
| `eth_blockNumber`, `eth_getTransactionReceipt` | block tracking, deployment and calibration receipts | present |

Option 7 also recognises RSKj's error strings for nonce too low or high, a known
transaction, an insufficient gas bump and `same hash already exists` (`ecdsa-stress-test.js`
84 to 88, `ERR_*` in `transaction-signer.js`). rustock's pool errors are its own wording
(`txpool.rs` 79 onwards), so a rejection rustock words differently is counted as a failure
and the VU re-syncs its nonce on the next iteration rather than skipping. That costs
throughput, not correctness; the amount is unknown until a run.

Accounts and keys. `conf/genesis_25M.json` funds the ten regtest accounts (`cd2a3d9f…`,
`7986b3df…`, and so on) plus four more and the bridge. Their keys are `keccak256("cow")`,
`keccak256("cow1")` to `keccak256("cow9")`: RSKj's regtest wallet derives them from those
seeds, and the fork ships the same ten in `regtest-wallet.example.keys`, loaded with
`--wallet-file`. On the mainnet seed the credited list in
`database-seed/seeds/mainnet/meta.json` is the same thirteen genesis addresses
plus two more; the ten cow accounts are among them, so the same key file serves both chains.

Someone has run the battery against the fork: commit d73ce31 "Four RPC defects the
rskj-k6-tests battery found (#332)" fixes genesis visibility, `net_version`,
`eth_newPendingTransactionFilter` and `rpc_modules`, and mentions 155 locally mined blocks.
`regtest-loadtest.example.toml` is the configuration they used. Its own comment says there
was no continuous mining then; the `AutoMiner` (`crates/rpc/src/evm.rs` 262 onwards) exists
now, see section 2.

Gaps, all harness-only:

- The node must be started with `--wallet-file`, `--mine --mining-coinbase`, `--dev-rpc`
  (the `evm_*` namespace, which `evm_startMining` lives in) and the account rate limiter off.
  Configuration, no code.
- Something must call `evm_startMining` once after the node is up, or the adapter below adds
  a flag that starts the miner at boot. Options 14 and 7 never call it.
- The error wording mismatch above. Not an adapter item: aligning error strings changes what
  the client answers, and the k6 side is the suite's. Measure the failure rate first.

## 2. Mining parity

RSKj, as the runtime image runs it (`docker/runtime/Dockerfile` entrypoint, `conf/rskj/rsk.conf`): `TimedMinerClient`
schedules each block after a delay drawn from an exponential distribution with median
`miner.client.medianBlockTime` (10 s in the image; the 5 s in `rsk.conf` is overridden by
the `-D` flag), floor 100 ms, the median scaled by the ratio of the current difficulty to the
first block's (`TimedMinerClient.scheduleNextMining`). With `skipPowValidation` the nonce is
0 and there is no search. The block is built by `MinerServerImpl` from the pool, gas limit
`targetgaslimit` 25M, and enters the chain through `EthereumImpl.addNewMinedBlock`, which
is `blockchain.tryToConnect`: the same `internalTryToConnect` that logs the breakdown line.

rustock has two ways to mine. `--mine` alone serves `mnr_getWork` and the three submit
methods for external mining software, rebuilding the template every
`--mining-refresh-secs` (60). The `AutoMiner`, started by `evm_startMining`, is a thread
that polls the pool every 250 ms and, whenever anything is pending, calls `mine_one_now`:
build a template, search a Bitcoin nonce, submit it to the same `complete_and_import` path
an external solution takes. There is no block time: blocks come as fast as a template can
be built and imported while the pool is non-empty, and no block is mined while it is empty.

What a template is (`crates/execution/src/mining/template.rs`, `build`): gas limit
inherited from the parent unchanged unless a target is set (`next_gas_limit`; the CLI
sets none, `MiningConfig::default`), so it stays 25M from the genesis on both chains;
minimum gas price likewise; timestamp wall clock, never at or before the parent; transactions
chosen as RSKj's `sortByPriceTakingIntoAccountSenderAndNonce` does (cluster by sender,
nonce order, merge by price) until the gas limit, then REMASC; the block executed once to fill
the roots. With RSKIP-144 active it is executed twice (once to learn the partition, once in
sublist order). Our chain has no RSKIP-144 height (`harness/regtest-config` reads the genesis
and leaves `rskip144` unset on RSKj's regtest), so `partition` returns early and the block is
executed once at build, then again at import, which is also RSKj's shape (build in
`BlockToMineBuilder`, execute again in `tryToConnect`).

What must match, and how:

| Setting | RSKj | rustock | Match |
|---|---|---|---|
| Block gas limit 25M | `-Dtargetgaslimit=25000000` | inherited from the parent | yes, both chains start at 25M |
| Block time, exponential, 10 s median | `TimedMinerClient` | none; the `AutoMiner` mines whenever the pool is non-empty | adapter `harness/timed-mining`: a scheduled miner with the same draw, floor and difficulty scaling, started by a flag |
| Proof of work skipped | nonce 0 | `mine_one` searches up to 16 × 2^18 nonces against `MAX / difficulty`; the genesis difficulty is 2^28, so on this chain the search would usually fail (`NoSolution`) | the same adapter: when `--skip-pow-validation` is on, submit with nonce 0 as RSKj does |
| RSKIP-144 off | `rskip144 = -1` | no height on RSKj's regtest; `execution_threads` default 1 | yes |
| Genesis, activations | `genesis_25M.json`, `rskip97 = 0` | `--genesis`, `--consensus-rule rskip97=0` | yes, as in replay |
| Pool: outdated after 10 blocks or 650 s | `reference.conf` | `PoolConfig` defaults 10 and 650 | yes |
| Pool: per-account slots | `accountSlots = 500` in `rsk.conf` | no per-account cap; `MAX_POOL_TRANSACTIONS` 8192 | not identical; see below |
| Account rate limiter off | `-Dtransaction.accountTxRateLimit.enabled=false` | `--account-tx-rate-limit false` (the TOML shows the section) | yes |
| Template refresh on new transaction | `updateWorkOnNewTransaction = true` | the `AutoMiner` builds a fresh template per block; the 60 s refresh is for `mnr_getWork` | equivalent for a timed miner that builds at mining time |
| Flush cadence | every 10 blocks, inside the connect (`onBestBlockMs`) | `commit_mined_block` flushes the trie store on every mined block | adapter `harness/timed-mining` (or a flag of its own): flush every N blocks on the mined path, N = `--import-flush-every` |
| Difficulty rule | RSKj's calculator, `rskip97` from 0 | the port of the same rule | yes, assumed from the replay hashes matching |

Pool limits cannot be made identical without changing the pool, which the adapter boundary
forbids. Under options 14 and 7 the load keeps at most 100 (option 14) or a few blocks' worth
(option 7, `BACKLOG_BLOCKS = 5`) of transactions in flight per account, 10 accounts, so
both pools stay under 1,000 entries and neither limit is reached. The report should say so
and check `txpool_status` during an arm.

What cannot be matched: the two nodes keep their own wall clocks and random draws, so the
block sequences differ (that is the nature of live arms, and the paired-cycle design
absorbs it); RSKj's template build runs in its own threads while mining candidates are
rebuilt on every new transaction (`updateWorkOnNewTransaction`), which is CPU the node
spends outside the measured connect; rustock's timed miner would build once per block. The
difference is in the unmeasured part of the node and in how much CPU each leaves for the
connect. On a 2 CPU container this can matter; the report has to name it.

## 3. Timing

rustock logs no per-block line on the mining path. `--breakdown-log` is read only by
`run_import_blocks` (`main.rs` 2573 and 3355 onwards), and `complete_and_import` calls
`process_and_commit`, the untimed sibling of `process_block_timed`. The mined block is
reported with one `info!` line, `Mined block #n … imported: IMPORTED_BEST`
(`mining/server.rs` 248), with no duration.

What is needed (adapter `harness/mined-block-timing`): `complete_and_import` times its stages
with the same `ImportTimings` and writes `breakdown_line` to the `--breakdown-log` file when
the result is `ImportedBest`. The mapping onto the import phases of `docs/timing-scope.md`:

| Phase | On the mined path |
|---|---|
| preambleMs | `take_template`, the executed-head check |
| initialValidationMs | `MergedMiningRule.validate` and `process_block`'s first stage (header, body rules, roots) |
| executeMs, trieSaveMs | `execute_block` inside `process_block` |
| postExecuteValidationMs | `process_block`'s check of the header against the result |
| switchChainMs | `commit_mined_block`: header, body, total difficulty, canonical update, exec head |
| saveReceiptsMs | `commit_receipts` (receipts, transaction index, bridge index), which `process_and_commit` runs before `commit_mined_block`, so the two phases swap order; the line reports them by name, so the analyzer does not care |
| onBestBlockMs | the `on_committed` hook (pool `remove_mined`, `evict_outdated`) and the trie flush |

`totalMs` would run from the start of `complete_and_import` to the log call, which is the
same scope as RSKj's `internalTryToConnect` on a mined block: validation, execution, state
root check, store, receipts, pool update, flush. Outside it on both sides: template build,
nonce handling, RPC. Two differences stay. The flush is on every block in rustock today
(the row above), and `process_block` re-executes a block the template already executed,
as RSKj does; the template's execution is outside `totalMs` in both.

The analyzer (`bin/analyze_block_breakdown.py`) parses `key=value` pairs and needs no change.
The live arm check this lab started from read a timestamp from the first 19 characters of each
line, which rustock's line does not carry; the lab's own check should use block numbers
above the seed tip instead, which both lines carry.

## 4. Validity without a hash gate

The arms mine different blocks, so the reference-hash gate of the replay campaigns does not
apply. Three checks replace it, all required for an arm to count:

1. **Cross replay.** After each arm, export its blocks (`ExportBlocks` from RSKj; the
   rustock side needs an export, see the adapter list) and replay them into the other client
   through the existing `bin/replay-docker.sh` path, from the same starting database. Every
   block must connect with the hash the miner gave it. A mismatch is a consensus finding
   against whichever client is wrong and stops the campaign, as today. The replay is the
   expensive part: at 30 to 60 ms per full block on the mainnet state, 200 blocks take
   seconds; the cost is starting the node on a clone, a few minutes each on the mainnet seed.
2. **Mined blocks are the node's own.** Every breakdown line has a block number above the
   seed tip (1159 or 9,003,579) and the log starts empty; exactly one k6 driver ran
   (checks kept from RSKj's live A/B benchmark).
3. **k6 client-side checks.** Option 14's threshold `tx_success_rate > 0.98` and option 7's
   revert sampling (`pollSample`) must hold; the k6 summary of each arm is kept with the arm.
   An arm with a success rate below the threshold measured a node that rejected the load and
   is discarded.

A fourth, cheap, comparison: per arm, transactions per block and gas used per block from the
breakdown lines. Two clients under the same load should fill blocks alike; a large gap in
`txCount` at equal `gasUsed` points at a pool or selection difference before any timing is
read.

## 5. Design

Arms and cycles as in the replay campaigns: a cycle is one RSKj arm and one rustock arm, the
order alternating; 6 cycles per scenario, up to 12 when the direction is consistent but not
significant. Each arm: fresh database (a new volume, or a hard-link clone of the seed), the
node started, k6 started against it, 30 minutes, k6 stopped, the breakdown log and the k6
summary collected, the node stopped, the blocks exported, the database dropped. Scenarios
`mainnet-sim` (option 14) and `ecdsa` (option 7), the same thresholds.

Machines:

- **Docker on this Mac**: the two clients in containers with the same limits. The replay
  campaigns use 4 CPUs and 6 GB; RSKj's live A/B benchmarks use 2 CPUs. Take 2 CPUs and 6 GB
  for the small chain and 10 GB on the mainnet seed, as they do, so the numbers can be read
  beside theirs. k6 runs on the host against `localhost:4444`.
- **Boton**: native binaries, counterbalanced as `bin/boton-campaign.sh` does: one slot RSKj
  on A and rustock on B, the next swapped. k6 runs on the box (`run-load.sh`), so the boxes
  need the k6 binary and Node, which the boxes' setup already installs. Small chain only
  until the rustock seed is on the boxes (`docs/mainnet-db-plan.md` decided sequential there).

Chains, in order:

1. **Small chain** from `genesis_25M.json`, empty database. Cheapest, and the k6 setup
   deploys its contracts in the first blocks. The first 20 blocks are dropped
   (`--min-block 20`), which also removes the deployment blocks.
2. **Mainnet seed**: RSKj on a clone of the seed volume's `/seed` with `node.props`;
   rustock on a clone of the converted seed (`docs/mainnet-db-plan.md` steps 4 and 5, plus
   `harness/mainnet-overrides`). The ten cow accounts are credited there, so the same wallet
   file works. Docker only.

Time per campaign: an arm is 30 minutes plus about 5 minutes of start, collection and cross
replay on the small chain, and about 10 on the mainnet seed (opening a 186 GiB database takes
minutes). Six cycles of two arms and two scenarios: 24 arms, about 14 hours on the small
chain and 16 on the seed; up to twice that at 12 cycles. Boton: 6 cycles of 2 slots of
about 40 minutes per scenario, 16 hours.

Scripts the lab needs:

- `bin/live-arm.sh <client> <artifact> <scenario> <db> <out-dir>`: one arm, both clients,
  both databases, Docker. The RSKj branch is `live-arm-mainnet.sh` with the lab's conf and
  image; the rustock branch runs `rustock-cli` with the replay flags of `clients/rustock.json`
  minus `--import-blocks`, plus `--wallet-file`, `--mine`, `--mining-coinbase`, `--dev-rpc`,
  `--rpc-host 0.0.0.0`, the timed-mining flag and `--breakdown-log`. Starts k6, waits, collects.
- `bin/check-live-arm.sh`: the checks of section 4, writing `consensus.json` and
  `summary.json` in the shape `bin/check-run.sh` writes, so `bin/stats.py` reads live and
  replay runs alike.
- `bin/lab.py`: a `--kind live` on `queue`, a `run_live` beside `run_docker` with the same
  cycle loop and lock handling (an arm holds the Docker slot as a long holder for 35 to 45
  minutes), and the cross replay called between arms.
- `bin/boton-campaign.sh`: a live slot beside the replay slot, deploying the k6 suite as
  `run-load.sh` does.
- `clients/rustock.json`: `live_args` beside `import_args`; a `conf/rustock-wallet.keys`
  copied from the fork's example file.
- `bin/report.py`: the live sections, with the k6 success rate and the cross-replay result
  per arm.

Adapter pull requests in rustock, each on `harness/<topic>` and merged into
`clients-lab/harness`:

- `harness/timed-mining`: a miner thread with RSKj's schedule (exponential, configurable
  median, 100 ms floor, median scaled by difficulty), nonce 0 when `--skip-pow-validation`,
  started by a flag (`--mine-timed <median>`), flush every N blocks on the mined path.
  Harness-only: it changes when blocks are mined and when the trie is flushed, not what a
  block contains or how it is executed.
- `harness/mined-block-timing`: the breakdown line on the mining path (section 3).
- `harness/export-blocks`: write the chain from height N as RSKj's `ExportBlocks` format, so
  the cross replay reads rustock's blocks with the existing `import-blocks` and `ConnectBlocks`.
  The decoder for that format exists (`parse_export_line`); the encoder is its inverse.
- `harness/mainnet-overrides`: already planned in `docs/mainnet-db-plan.md`.

## 6. Risks and unknowns, ranked

1. **Proof of work on this chain.** Read in the code, not run: `mine_one` gives up after
   about 4 million nonces and the genesis difficulty is 2^28, so until `harness/timed-mining`
   lands, `evm_startMining` would likely mine nothing on `genesis_25M.json`. The first smoke
   test should be one `evm_mine` on the small chain.
2. **The sync service's view of the state root.** Issue #323 (named in commit d73ce31): a
   locally mined block advances the committed head without telling the sync service, which
   repairs it on its tick (`resync_state_root_with_exec_head`). Two warnings in 155 blocks
   then. With no peers nothing else moves the head, but a repair that re-reads the root is
   work the node does between blocks, and a repair that goes wrong would reject the next
   template's parent. Watch the log for the warning during the smoke test.
3. **Load shape differs between the arms.** Option 14 paces itself from the observed block
   time and option 7 from the observed gas limit and backlog; both react to the node. A node
   that rejects more sends (the error wording of section 1) or answers RPC more slowly gets
   less load, so fewer blocks qualify as full and the trimmed mean is over a different
   population. Report qualifying blocks, `txCount` and the k6 success rate per arm, and
   discard arms under 20 qualifying blocks.
4. **Unmeasured CPU.** The template build, the RPC server and the pool run beside the
   connect and compete for the 2 CPUs. RSKj rebuilds a candidate on every new transaction,
   rustock once per block. `totalMs` would then include contention that the replay does not
   have, and the two clients would carry different amounts of it. Mitigation: 4 CPUs in
   Docker, and a sensitivity check at 2.
5. **Cross replay on the mainnet seed.** Each cross replay opens a second clone of a
   186 GiB database; disk and minutes per arm. The clone budget in `docs/mainnet-db-plan.md`
   step 1 was written for one clone at a time.
6. **No k6 on the Boton boxes for rustock yet.** The boxes' setup installs the suite for
   RSKj's runs; the lab's Boton slot has never started k6. Inferred to be a copy of `run-load.sh`.
7. **`eth_mining` answers false** in rustock whatever the miner does (`eth::eth_mining`).
   Neither option 14 nor 7 reads it; the basic suite does. Not a blocker; noted so nobody
   reads it as "not mining".
8. **Error strings.** Section 1: unquantified until a run.

## Smoke tests (2026-10-27 night to 2026-10-28 morning)

Three one-cycle campaigns on the small chain (ecdsa, k6 option 7, empty database), 5 and
10-minute arms (`CLIENTSLAB_ARM_MINUTES`), rustock first on 428086b then cb6d948:

1. `2026-10-27-c4`: rustock's mined headers were version 0 on a chain whose RSKj peers
   emit version 2. RSKj's `decodeHeader` read the merged-mining header as the version and
   failed with a NullPointerException. Fixed: `harness/mined-header-version` fb10dc4.
2. `2026-10-28-c1`: with the version right, RSKj refused `Invalid block header size: 21`.
   rustock's regtest template omitted `ummRoot`, deciding it from
   `ChainConfig::activation_heights` (papyrus200 never on regtest) while the hardfork
   ladder, as rskj's regtest.conf, has it at genesis. Fixed: second commit 24b0d36 on the
   same branch (`docs/prs/harness-mined-header-version.md`).
3. `2026-10-28-c2` (rustock cb6d948): **both cross replays pass**. RSKj's 37 blocks into
   rustock, rustock's 39 into RSKj, every hash equal. The pipeline is validated end to end.
   The cycle was still discarded: RSKj's arm had 17 qualifying blocks, under the 20 the
   config asks for, because a 10-minute arm mines about 40 blocks and the first 20 are
   dropped. Thirty-minute arms (the config default) give about 120.

Per-arm figures for later comparison (10-minute arms, 2 CPUs, trimmed mean of qualifying
blocks' `totalMs`): RSKj 220.6 ms (c2) and 227.1 ms (c1). rustock's own numbers come from
the first full campaign.

The first full campaign, `2026-10-28-c3` (6 cycles, 30-minute arms, ecdsa, rustock
cb6d948), started 2026-10-28 11:3xZ; about seven hours of the Docker slot.

### First full cycle (2026-10-28-c3): rustock's arm discarded twice over

RSKj's arm counted (128 blocks, 109 qualifying, k6 100%, cross replay ok). rustock's did
not, for two reasons the smoke tests were too short to show:

1. **k6 success rate 68%**, under the 80% floor: 4305 stress calls refused as "transaction
   nonce too high". The lab's RSKj runs with `transaction.accountSlots = 500` (what the
   k6 suite assumes); rustock had rskj's default 16 as a constant. Section 1 above
   guessed at the error wording; this is it. Fixed as a setting both clients now get:
   `harness/account-slots` (1c413d3, `docs/prs/harness-account-slots.md`),
   `--account-slots 500` in `live_args` and `mainnet_live_args`.
2. **129 breakdown records for 123 exported blocks**: rustock's timed miner keeps going
   through `docker stop` and the blocks it mines while shutting down are logged but not
   exported. `bin/live-arm.sh` now calls `evm_stopMining` before reading the final height.

Also visible in the k6 summary: rustock's RPC answered in 906 ms on average (p95 3.5 s)
against RSKj's 6.6 ms (p95 28 ms). Part of that is the refused sends being retried; the
rerun will say how much. Rerun: `2026-10-28-c4`, rustock 1909b1c.

### First full result (2026-10-28-c4): rustock 2.94x faster on its own blocks

Six cycles, 30-minute arms, ecdsa, rustock 1909b1c with `--account-slots 500` and
`evm_stopMining` before the export. Every arm counted: cross replays clean both ways in all
six cycles, every log holding exactly its exported blocks, k6 success 99.99% or 100%, 88 to
121 qualifying blocks per arm. `campaigns/2026-10-28-c4/report.md`.

| client | blocks mined per arm | qualifying | totalMs, trimmed mean |
|---|---|---|---|
| RSKj | 120 to 140 | 102 to 121 | 227.3 |
| rustock | 107 to 138 | 88 to 119 | 78.1 |

rustock faster in 6/6 cycles (2.69x to 3.08x), median -65.97%, sign-test p = 0.03125. The
same order as the sequential ecdsa replays on the small chain, so mining its own blocks costs
rustock nothing extra. Both clients mined blocks of comparable fill (gas used 2.5 to 3.4
billion per arm, no pattern by client), so the paired design has little to absorb.

The RPC latency seen in c3 was the refused sends: with 500 account slots, k6's
`rpc_req_duration_ms` averaged 0.9 to 1.3 ms for rustock (p95 2.3 to 3.2 ms) and 2.5 to
2.7 ms for RSKj (p95 5.6 to 6.5 ms), with no failed requests in any arm.

Open from this campaign: rustock's `onBestBlockMs` still reads 0.1 ms against RSKj's 0.0
(both negligible on this path), and `initialValidationMs` is 6.8 ms in RSKj against 0.1 in
rustock, the one phase besides execution with a visible difference.

### Mainnet seed (2026-10-28-c5): blocked on the RSKj seed

`2026-10-28-c5` (live ecdsa on the mainnet seed) failed in its first arm with "no seed in
the seed volume": this Mac's copy of the RSKj seed was deleted on 2026-10-28
to make room for rustock's seed compaction (`docs/mainnet-db-plan.md`), and the boxes' copies
went the same way. Only `rustock-seed` (148 GB) is in the volume. Rebuilding needs the
source tarball on the external disk "Backup 1" (not attached) and `bin/seed.sh extract`
then `bootstrap`; a rebuild now funds the senders from
the bridge instead of minting, so its tip and state differ from the seed rustock's was
converted from, and rustock's seed would have to be converted again for the two to be the
same chain. Live mining on the mainnet seed waits on that decision.

### Mainnet seed (2026-10-28-c6): rustock mines blocks RSKj rejects

Both seeds were rebuilt on 2026-10-28 (`docs/mainnet-db-plan.md`): the RSKj seed with
`bin/seed.sh extract` and `bootstrap` (tip #9003567, the 15 senders funded from the bridge),
rustock's converted from it. `2026-10-28-c6` (live ecdsa on that seed, rustock 1909b1c, 10g
memory) ran its first cycle: RSKj's arm counted (131 blocks, 113 qualifying, k6 100%, cross
replay ok); rustock's arm mined 138 blocks, k6 100%, 119 qualifying, and RSKj rejected the
first of them, #9003569, as an invalid block:

```
Tx gas price=26065600 is above the cap. Block=448584413f...
```

The cap is RSKIP252 (`BlockTxsMaxGasPriceRule`): no transaction in a block may pay more than
100 times the block's `minimumGasPrice`. The block's minimum was 587 wei; the transaction
paid 26,065,600 wei, 44,000 times that. Two differences between the clients produced it, and
the seed is what exposed them.

1. **rustock's miner does not apply the cap.** `select_transactions` in
   `crates/execution/src/mining/template.rs` drops transactions under the minimum and nothing
   else. RSKj's `MinerUtils` drops the ones over the cap too (`isHighGasPriced`). rustock has
   the import-side rule (`crates/core/src/validation/block_rules.rs`, which would reject this
   block coming from a peer) but does not run it on the blocks it seals. This is the
   consensus finding: rustock produced 138 blocks that the network's validators refuse.
2. **rustock's `eth_gasPrice` ignores the fee-market gate.** Both clients prime a
   `GasPriceTracker` from the database (the 25th percentile of the last 512 transactions,
   floored at 1.1 times the head's minimum). RSKj only answers with it when
   `isFeeMarketWorking()` (the last 50 blocks at least 90% full on average); otherwise
   `eth_gasPrice` is the head's minimum times 1.1 (`EthereumImpl.getGasPrice`). rustock's
   `eth_gas_price` returns the tracker's answer unconditionally. The seed's last 512
   transactions are mainnet's, paying about 26 M wei when the minimum was 23.7 M; the
   bootstrap then walked the minimum down to 587 over its 1060 blocks. So k6 priced its
   transactions at 645 wei on RSKj and 26,065,600 wei on rustock, the same call on each.
   Not a consensus rule, but it is what fed the miner transactions over the cap.

On mainnet itself neither shows: the minimum sits near the market price and the cap is 100
times away. The lab's seed has a minimum 40,000 times under the history's prices, and the
one client that steers `eth_gasPrice` by that history, with a miner that does not check the
cap, mines invalid blocks. The old seed (c4 and before) had minimum 0, where the cap does
not apply at all.

A third asymmetry, harmless here but worth a setting: RSKj's miner steers `minimumGasPrice`
toward `miner.minGasPrice` (0 by default) one percent per block, 582 down to 193 over the
arm; rustock's template keeps the parent's (587 throughout) because its
`min_gas_price_target` is unset.

Per-arm figures from the cycle, for the record only (the rustock arm does not count): RSKj
131 blocks in 1847 s, rustock 138 blocks in 1947 s; both arms gas used 3.2 billion.

Both fixes belong to the client, not the harness: the miner's cap is block production, the
RPC gate is node behaviour. Either reported upstream, or the lab pins k6's gas price to the
head's minimum times 1.1 on both arms (the same rule RSKj applies, applied by the harness)
and runs the comparison while the findings stand. That choice is the user's.

### Mainnet seed result (2026-10-29-c1): rustock 2.73x faster on its own blocks

The rerun of c6 with k6 pricing every transaction at the head block's `minimumGasPrice`
times 1.1 on both arms (`live.k6_gas_price`, `GAS_PRICE_RULE` in the k6 suite). Six cycles,
30-minute arms, ecdsa, rustock 1909b1c, 10g memory. Every arm counted: cross replays clean
both ways in all six cycles, k6 100% everywhere, 87 to 120 qualifying blocks per arm.
`campaigns/2026-10-29-c1/report.md`.

| client | blocks mined per arm | qualifying | totalMs, trimmed mean |
|---|---|---|---|
| RSKj | 110 to 138 | 92 to 120 | 251.5 |
| rustock | 106 to 123 | 87 to 104 | 93.4 |

rustock faster in 6/6 cycles (2.43x to 2.84x), median -63.43%, sign-test p = 0.03125. Both
clients are about 10% slower per block than on the empty database (c4: 227.3 and 78.1 ms),
the state being a mainnet trie, and the ratio holds. Execution is the whole difference
(226.6 against 90.7 ms); `saveReceiptsMs` is 10.4 against 0.9 and `initialValidationMs` 5.9
against 0.1, both small.

One harness lesson from cycle 6: RSKj's timed miner connected two blocks of its own at
#9003625 within 44 ms and kept the second, so its log held 117 records for 116 exported
blocks and the own-blocks check discarded the arm. `bin/check-live-arm.sh` now allows such
a sibling (a block of the node's own, inside the arm's range, replaced at the same height),
reports it as `own_siblings`, and keeps its lines out of the timing; anything else the
export lacks still discards the arm. The arm was re-checked under that rule, not re-mined,
and `bin/lab.py` now judges a campaign whose cycles are already complete instead of
starting another cycle.

Next: `2026-10-29-c2`, mainnet-sim under k6 option 14 on the same seed, the first live run
of that scenario.

### mainnet-sim live (2026-10-29-c2): the suite's ERC-20 bytecode was never a contract

The first live run of mainnet-sim (k6 option 14) on the mainnet seed stopped after one cycle.
RSKj's arm counted (125 blocks, 107 qualifying, k6 100%). rustock's arm mined 107 empty
blocks: k6's setup failed on rustock at the first step, the ERC-20 deployment, with
`Invalid data` from `eth_sendTransaction`, and never sent a transaction.

The cause is in the k6 suite. `utils/contracts/erc20.js` held an `ERC20_BYTECODE` of 2513 hex
digits, an odd number, so it was never a byte string. The two clients disagree on what to do
with it:

- RSKj's `HexUtils.stringHexToByteArray` left-pads a zero nibble and goes on. The init code
  then starts with `06 08 06 04 ...`, a `MOD` on an empty stack, so the deployment fails after
  burning everything it was given: `eth_estimateGas` answered the whole block gas limit, the
  suite capped it at 22.5 M and sent it, and the receipt carried a contract address with no
  code behind it. Every `erc20_transfer` and `erc20_approve` of the scenario since then has
  been a call to an empty account, which succeeds and costs 21,000 gas plus calldata.
- rustock's `parse_hex` refuses the odd string, as the JSON-RPC spec reads. Its
  `eth_estimateGas` on the same object answered 53,000 instead of an error, which is worth a
  line upstream.

So mainnet-sim's "ERC-20" share has been inert in every sample the suite ever mined, on this
lab and on perf-lab, whose `repos/rskj-k6-tests` carries the same constant. The deployment
transaction itself, 22.5 M gas of failed execution in block 2 of each sample, is inside the
first 20 blocks that every analysis drops.

Fixed in the k6 fork (57c00ac): `ERC20_BYTECODE` is now `contracts/ERC20.sol` compiled as its
header says, solc 0.8.17 with the optimizer at 200 runs, 1907 bytes. The source pre-mints to
the deployer and reverts transfers from empty balances, so under the scenario nine of ten
senders' transfers revert at the EVM and the tenth's succeed; k6 counts both as RPC success,
as its comment says. A mainnet-sim sample mined with this suite is a heavier block than the
earlier ones, with real storage writes in the ERC-20 share, and is not comparable to the
earlier mainnet-sim numbers. The rerun of this campaign is the first measurement of the
scenario as described.

### mainnet-sim live (2026-10-29-c3): rustock's blocks are 60% full

With the ERC-20 fixed, both arms of cycle 1 deployed the three contracts at the same gas
estimates and k6 held 100% on both. RSKj's arm counted (114 blocks, 96 qualifying, 166
transactions and 24.7 M gas per block). rustock's arm was discarded: 115 blocks, 78
transactions and 12.6 M gas per block, none at 90% of the limit, with k6 reporting 100
pending transactions per account throughout, its own ceiling, so the load was there and
rustock did not take it.

The cause is the miner's packing rule. rustock's template adds each candidate's declared
gas limit and stops at 25 M; RSKj executes candidates as it packs and charges only the gas
they use. k6 option 14 declares 21,000, 100,000, 300,000 and 1,500,000 per transaction type
and uses about 60% of that, so RSKj's blocks carry 40 to 43 M of declared gas and rustock's
exactly 25 M. Option 7 declares close to what it uses, which is why the ecdsa live campaigns
never showed it. Written up for upstream in
`docs/issues/rustock-miner-packs-by-gas-limit.md`.

This is block production, not a harness setting, and the arms cannot be made comparable by
loosening the qualifying threshold: a 60% block is a different workload. Tightening k6's
declared limits would hide the difference rather than measure it, and could not fit both the
transfers that succeed and the ones that revert. mainnet-sim live on rustock waits for the
miner fix; the replay comparison on mainnet-sim is unaffected, since replay imports RSKj's
blocks. The ERC-20 fix stands and applies to the next re-mining of the mainnet-sim samples.
