# --allow-chain-overrides: rskj's activation overrides on a copy of mainnet

Branch `harness/mainnet-overrides` in `clients/rustock`, on `clients-lab/harness` (024e203,
which merges `harness/regtest-config`, `import-blocks`, `block-timing` and `dockerfile` on
Lerner's `main` 43dc5e5). One commit, f8ead22.

## What and why

The lab's mainnet samples are blocks RSKj mined on top of perf-lab's mainnet seed (tip
#9,003,579) under `node.props`: mainnet's activation heights, plus `reed810`, `tbd1000`,
`rskip351` and `rskip535` at #9,002,504, `rskip536` at #8,804,200, and no real merged mining.
RSKj takes those as `-D` overrides. rustock's harness branch refused every chain option on
chain id 30, so the converted seed could not be replayed into. This adds the opt-in and the
flags:

- `--hardfork name=height`: rskj's `blockchain.config.hardforkActivationHeights`, by rskj's
  names, `-1` taking the upgrade off the ladder. Repeatable.
- `--allow-chain-overrides`: take `--hardfork`, `--consensus-rule`, `--skip-pow-validation`,
  `--min-gas-limit` and `--max-gas-limit` on mainnet and testnet. `--genesis` stays refused
  there: a genesis file would make it another chain, and mainnet's genesis is built in. The
  node warns at startup that it must not follow the real network.
- `--consensus-rule` now also takes `rskip351`, `rskip535` and `rskip536`, which the execution
  ladder schedules apart from their upgrade, and `rskipUMM` at papyrus200's height only,
  because nothing in rustock reads it on its own (the `ummRoot` field is positional in the
  header decoder).
- The same settings in the `[chain]` section of `--config`: `hardforks`, `allow_overrides`.

The overrides reach every reader of the schedule, the same way the regtest ones do.
`ActivationHeights` (header decoding and hashing, difficulty, merged mining) is set from the
names it carries, `reed810` among them as RSKIP-144's height, which is what decides whether a
V2 header's lone trailing item is sublist edges or a base event. `RskHardforkConfig`
(execution, REMASC, Bridge) is built with `with_rskj_overrides`, so `has_rskip144`,
`has_rskip351`, `has_rskip535` and `has_rskip536` answer per the overrides. `rskip97` follows
`orchid` as `reference.conf` ties them, unless `--consensus-rule rskip97` says otherwise.

Names rustock reads at one fixed height per chain (`bahamas`, `afterBridgeSync`, `hop401`)
are accepted at that height and refused at any other, so a schedule it cannot run is refused
at startup. `orchid060` and `tbd1000` are accepted and logged as read by nothing. `tbd1000`
only turns on RSKIP-559 (deterministic pegout sorting in the Bridge, rskj
`ConsensusRule.java` and `PegoutsWaitingForConfirmations.java`), which rustock does not
implement and no block of the lab's samples exercises: the samples carry no Bridge
transactions. The report has to say so.

One change in the ladder itself: `active_upgrade` is now the highest rung scheduled at or
below the block, rather than the last rung by height. On the built-in tables, which are
ordered by height and by rung alike, that is the same rung at every block; on a ladder with
`reed810` scheduled above `vetiver900` it keeps vetiver900's rules in force instead of
stepping the chain back to reed810's. Without the opt-in, mainnet and testnet are unchanged.

## How to test

```bash
cargo test -p rustock-core -p rustock-execution --lib -- hardfork override_tests header::tests
cargo test -p rustock-cli --bin rustock-cli -- genesis_tests config_file
```

`mainnet_without_the_opt_in_is_untouched` refuses every override on chain id 30 without the
flag and holds a plain mainnet node to its built-in heights, bounds and ladder;
`the_seed_schedule_applies_on_mainnet_with_the_opt_in` passes the lab's full flag set and
checks the ladder, the refusal of `--genesis` and of a moved `hop401`;
`the_seed_schedule_turns_reed810_on_above_vetiver900` and `mainnet_without_overrides_is_unchanged`
cover the execution ladder; `a_reed810_override_turns_a_lone_trailing_item_into_edges` decodes
one V2 header under both schedules. The end-to-end check is the lab's
`bin/replay-docker.sh rustock <image> ecdsa@mainnet`, whose `mainnet_import_args` in
`clients/rustock.json` carry every entry of `node.props`.
