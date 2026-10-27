# Regtest options for running the chain an rskj regtest node runs

Branch `harness/regtest-config` in `clients/rustock`, on `lerner/main` (43dc5e5). One commit.

## What and why

rustock's regtest is its own chain, so blocks mined by an rskj regtest node do not connect to
it. Four things differ: the genesis, the Bridge federation REMASC pays, the gas-limit bounds,
and the proof of work (chains mined for tests carry none). This adds regtest-only options that
make rustock run rskj's chain:

- `--genesis <file>` reads an rskj genesis JSON file. The genesis hash comes out as rskj's: the
  difficulty is hashed as the file writes it (`0x0010000000` keeps its leading zero byte), the
  state root is the root of the state built from the file, and the precompile accounts rskj
  creates at genesis on regtest are created. The chain also takes rskj's regtest federation
  (`BridgeConstants::rskj_regtest`, from rskj's `BridgeRegTestConstants`). Without it REMASC
  pays no federator, and the zero-value payments rskj makes at its first payout block never
  create the three federator accounts.
- `--consensus-rule name=height` is rskj's `blockchain.config.consensusRules`. Only `rskip97`
  is accepted; it is the one rule rustock reads on its own height.
- `--min-gas-limit` and `--max-gas-limit` set the header gas-limit bounds (rskj: 3,000,000 and
  none).
- `--skip-pow-validation` is rskj's `miner.server.skipPowValidation`: the merged-mining rule
  passes without looking at the proof.
- A `[chain]` section of the `--config` file holds the same settings. All of them are refused
  on mainnet and testnet.

One change reaches the header decoder. After an RSKIP-351 version byte, a single trailing item
is the RSKIP-144 sublist edges where RSKIP-144 is active and the RSKIP-535 base event where it
is not, which is how rskj's `BlockFactory` tells them apart. rustock assumed edges. rskj's
regtest has `rskip144 = -1` and `rskip535 = 1`, so its V2 headers were read with the empty base
event taken for edges. The hash of a header read back from the store came out wrong, and REMASC
at block 15 picked the wrong block hash. `ActivationHeights` now carries `rskip144`: testnet
gets its `reed810` height and decodes as before; mainnet (`reed810 = -1`) and rustock's own
regtest get none. `Header::decode_with_activations` takes the heights explicitly, and the
`Decodable` impl passes the installed ones.

What rustock still cannot express: rskj regtest disables `arrowhead631` and `afterBridgeSync`,
while rustock's regtest ladder starts at `vetiver900` with everything before it active. Both
change only Bridge behaviour, and the lab's samples carry no Bridge transactions.

## How to test

```bash
cargo test -p rustock-core -p rustock-cli
```

`an_rskj_genesis_file_gives_rskjs_genesis_hash` loads the lab's genesis file and checks rskj's
hash, 0x227d8e8d…; `a_v2_header_without_rskip144_carries_a_base_event_not_edges` decodes block 1
of an rskj regtest chain; `test_merged_mining_rule_skip_pow_validation` and
`chain_options_apply_on_regtest_only` cover the rest. The end-to-end check is in
`harness/import-blocks`.
