# rustock's `eth_gasPrice` answers the tracker without rskj's fee-market gate

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-29, campaign
`2026-10-28-c6`, rustock 1909b1c (`clients-lab/comparison`, upstream base 43dc5e5).
Not a consensus rule; it is what fed the miner the transactions in the companion issue
on the RSKIP252 cap.

## What happens

`crates/sync/src/gas_price.rs` reproduces rskj's `GasPriceTracker`: the 25th percentile of
the last 512 transactions' gas prices, floored at 1.1 times the head's `minimumGasPrice`,
primed from the database at start. `eth_gas_price` in `crates/rpc/src/eth.rs` returns
`tracker.gas_price()` whenever a tracker is present.

rskj does not. `EthereumImpl.getGasPrice` answers with the tracker only while
`isFeeMarketWorking()` (the last 50 blocks at least 90% full on average); otherwise it
returns the head's `minimumGasPrice` times `minGasPriceMultiplier` (1.1). rustock has
`is_fee_market_working` and logs it at priming ("fee market working: false") but
`eth_gasPrice` never consults it.

## How it showed

A mainnet copy at tip #9003567 whose last 512 transactions paid about 26 M wei (mainnet's
market, minimum 23.7 M at the time) and whose `minimumGasPrice` had since been walked down
to 587 wei by 1060 near-empty blocks. On the same chain, under the same load:

| client | fee market working | `eth_gasPrice` | what k6 paid |
|---|---|---|---|
| rskj | false | head minimum x 1.1 | 645 wei |
| rustock | false | 25th percentile of history | 26,065,600 wei |

44,000 times the minimum, over the RSKIP252 cap of 100 times, and rustock's miner sealed
them. On mainnet the two answers are close, since the minimum tracks the market.

## Fix

In `eth_gas_price`: if the tracker says the fee market is not working, answer the head's
`minimumGasPrice` times 1.1 (the multiplier rskj's `minGasPriceMultiplier` holds, default
1.1), else the tracker's price, as rskj does. A test: with a primed tracker whose block
window is under 90% full, `eth_gasPrice` equals the head minimum times 1.1 and not the
percentile.

rskj has this test already: `EthereumImplTest.getGasPrice_returns_correctedBestBlockValue_when_feeMarketWorking_is_false`
(with its `..._true` twin). rustock's `test_eth_gas_price_uses_the_tracker` and
`test_eth_gas_price_falls_back_to_the_block_minimum` cover a tracker present or absent, never
the fee-market flag; porting rskj's pair is the natural start.

## Status

Fixed on 2026-10-30, rustock branch `fix/miner-gas-packing-cap-and-gasprice-gate` (on top of
1909b1c), uncommitted until the user says so. `GasPriceSource` gained `is_fee_market_working`;
`eth_gas_price` answers the head minimum times 1.1 (rskj's `rpc.minGasPriceMultiplier`
default, the same double-then-truncate arithmetic: 587 wei gives 645) while the market is not
working, the tracker's price otherwise. Tests ported: rskj's `getGasPrice_returns_...` pair as
`test_eth_gas_price_uses_the_tracker` and
`test_eth_gas_price_returns_corrected_best_block_value_when_fee_market_is_not_working`, plus
`corrected_minimum_gas_price_truncates_like_rskj`.
