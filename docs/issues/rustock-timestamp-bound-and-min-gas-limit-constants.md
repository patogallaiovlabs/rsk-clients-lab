# rustock's future-timestamp bound and minimum gas limit differ from rskj's constants

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-30 by mapping rskj's tests
(e507f45) to rustock's (branch `fix/miner-gas-packing-cap-and-gasprice-gate` on 1909b1c); the
full table is `docs/rskj-test-parity.md` in rustock.

Node-local acceptance rules, not consensus; they decide which valid blocks a node takes.

## What happens

`HeaderVerifier::default_rsk` (`crates/core/src/validation/mod.rs`) wires
`TimestampRule::new(15)`: a block more than 15 s ahead of the node's clock is refused.
rskj's `BlockTimeStampValidationRule` uses `Constants.newBlockMaxSecondsInTheFuture`: 60 on
mainnet, 540 on testnet, 0 on regtest, where zero turns the whole rule off, parent check
included. `ChainConfig.max_future_block_time` carries 540 for mainnet and testnet and is read
nowhere.

`ChainConfig.min_gas_limit` (`crates/core/src/config.rs`) is 5,000 on mainnet and testnet;
rskj's `Constants.getMinGasLimit` is 3,000,000 on every network, and `GasLimitRule` rejects a
header under it. Nothing on mainnet goes near either bound.

## How it shows

A block timestamped 16 to 60 s ahead of rustock's clock is refused where rskj accepts it; a
regtest block rskj takes with any timestamp, rustock may refuse. rskj tests the bound in
`BlockTimeStampValidationRuleTest.blockInTheFutureLimit` and `.blockInTheFuture`, and the gas
limit in `GasLimitRuleTests`.

## Fix

Take the bound from the chain configuration (60, 540, 0 with rskj's meaning of zero) and
drop the unused field or use it; set `min_gas_limit` to 3,000,000. Port the three rskj tests.

## Status

Fixed on 2026-10-30, rustock branch `fix/miner-gas-packing-cap-and-gasprice-gate`.
`HeaderVerifier::default_rsk` reads `ChainConfig.max_future_block_time`, now 60 on mainnet, 540
on testnet, 0 on regtest, and `TimestampRule` treats zero as rskj does: the rule is off, parent
comparison included. `min_gas_limit` is 3,000,000 on all three networks (rskj's regtest genesis
declares 10,000,000, so nothing rskj accepts is lost). Tests ported: the nine remaining
`BlockTimeStampValidationRuleTest` cases and the three `GasLimitRuleTests`.
