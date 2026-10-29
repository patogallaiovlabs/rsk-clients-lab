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
