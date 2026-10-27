# --mine-timed: mine on rskj's regtest clock, nonce 0 without PoW, flush every N

Branch `harness/timed-mining` in `clients/rustock`, on `clients-lab/harness` (024e203). One
commit.

## What and why

rskj's regtest, as the lab runs it, mines with `TimedMinerClient`: one block per scheduled tick,
the delay to the next tick drawn from an exponential distribution with median
`miner.client.medianBlockTime`, floored at 100 ms and scaled by the ratio of the current
difficulty to the first block's. With `skipPowValidation` the Bitcoin block is submitted with
nonce 0 and nothing is searched. rustock had no block time: the `AutoMiner` behind
`evm_startMining` mines as fast as templates build while the pool is non-empty, and never while
it is empty, and its bounded nonce search gives up at the 2^28 difficulty of the lab's genesis.

`--mine-timed <median>` (`10s`, `500ms`) adds a port of that schedule as a thread beside the
`MinerServer`. Each step of the port names the rskj line it mirrors
(`rskj-core/src/main/java/co/rsk/mine/TimedMinerClient.java`):

- the delay, `scheduleNextMining` 186 to 194: median scaled by the difficulty ratio, a
  non-finite or non-positive result falling back to the base median, mean = median / ln 2,
  delay = -mean * ln(1 - u) with u uniform in [0, 1), truncated to whole milliseconds, floor
  100 ms;
- the difficulty ratio, `mineBlock` 115 to 128: current difficulty = `MAX / target` of the work
  just taken, the first one seen is the baseline with scale 1, afterwards scale = current /
  baseline, and 1 again when that is not finite or not positive;
- nonce 0 when proof of work is not validated, `mineBlock` 130 to 138;
- the first block scheduled rather than mined at once, `start` 83; a failed block still
  schedules the next, `mineBlock` 152 to 158.

Left out: `hasBetterBlockToSync` (100 to 108), which pauses the miner behind a peer; the node
has no equivalent handle and the regtest chain has no peers. When proof of work is validated,
the search is the fork's bounded `mine_one` search rather than rskj's unbounded `findNonce`.

Blocks are mined whether or not the pool holds anything, as rskj does. The template and the
submit path are the fork's: `build_work`, the coinbase and Bitcoin block of
`mining::coinbase`, `submit_bitcoin_block`, `complete_and_import`. What a block contains and
how it executes is unchanged.

Three things around the miner change:

- `--flush-every <N>` (default 10, rskj's `blockchain.flushNumberOfBlocks`): mined blocks flush
  the trie every N best blocks instead of every block. The executed head still moves on every
  block, so the next template builds on the block just mined; between flushes the state lives
  in the trie store's memory, as it does during a catch-up.
- `StoreChainAccess::mainchain` hands the template builder each header under the hash it is
  stored by. The genesis built from an rskj JSON file hashes over the file's difficulty bytes
  as written, which its decoded form no longer has, so the first template on such a chain named
  a parent no node knows (`ParentNoLongerHead` on every submission).
- The miner's `BlockProcessor` is wired like the node's: the same caches, threads and, on a
  chain from an rskj genesis file, rskj's regtest Bridge constants. A bare processor ran REMASC
  against the built-in federation, so block 15 (the first payout, maturity 10 plus the synthetic
  span) reached a state root no node with the right constants reproduces: a re-import of the
  mined chain failed there with `stateRoot`.

The miner starts with the node. `evm_stopMining` pauses it and `evm_startMining` resumes it,
through a `BackgroundMiner` trait in the rpc crate that the pool-polling `AutoMiner` also
implements; a harness that calls `evm_startMining` once at the start, as k6 does, finds it
already running and is answered `true`. `--mine-timed` requires `--mine` and composes with
`--mining-coinbase`, `--wallet-file`, `--dev-rpc` and `--breakdown-log`. The file config takes
`[mining] timed` and `flush_every`.

For the lab: the node runs with `--mine --mining-coinbase <addr> --mine-timed 10s --flush-every
10 --skip-pow-validation --consensus-rule rskip97=0 --wallet-file conf/rustock-wallet.keys
--dev-rpc --account-tx-rate-limit false`, and nothing has to call `evm_startMining`.

## How to test

```bash
cargo test -p rustock-execution mining
cargo test -p rustock-cli --bin rustock-cli block_time config_file
cargo test -p rustock-rpc evm
```

`timed::tests` check the schedule: the draw at u = 0.5 is the median, quantiles at 0.25, 0.75
and 0.9 are the exponential's, draws are floored at 100 ms, twenty thousand draws from the real
generator have the configured median and a mean of median / ln 2, and the first target sets
the baseline while later ones scale the median. `mining::tests` mine through the server: nonce
0 is accepted on a chain without proof-of-work validation at a difficulty the search cannot
meet and refused with `SelfCheck` on one with it; `flush_every` 3 flushes on the third and
sixth of seven blocks while the executed head follows every block; the thread mines several
blocks in 1.5 s at the floor median and none after `stop`; the template names its parent by
the stored hash.

By hand, on the lab's genesis with a 1 s median and `--breakdown-log`: blocks arrive at about
the median (17 blocks in 25 s in the check, median gap 1.4 s, mean 1.3 s against an expected
1.44 s), transactions sent with `eth_sendTransaction` land in the next block, and the chain
exported with `--export-blocks` re-imports from an empty data directory with every hash equal.
