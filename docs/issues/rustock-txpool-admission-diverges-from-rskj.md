# rustock's transaction pool admits what rskj's `TxPendingValidator` refuses

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-30 by mapping rskj's tests
(e507f45) to rustock's (branch `fix/miner-gas-packing-cap-and-gasprice-gate` on 1909b1c); the
full table is `docs/rskj-test-parity.md` in rustock.

Not consensus; it is what the node relays and what its miner may pick.

## What happens

`validate_tx` in `crates/sync/src/txpool.rs` lacks four of rskj's steps:

- **The 80x price cap.** `TxValidatorMaximumGasPriceValidator` with `TxGasPriceCap.FOR_TRANSACTION`
  refuses a transaction priced over 80 times the best block's minimum once RSKIP252 is active.
  rustock applies only the block's 100x cap, and only at selection and import.
- **The sublist gas limit.** With RSKIP144 and RSKIP351 active, `TxPendingValidator` compares
  the gas limit with the larger sublist limit (`BlockUtils.getSublistGasLimit`), not the
  block's. rustock compares with the block's; the sublist arithmetic exists in
  `crates/execution/src/mining/partition.rs` and the pool does not use it. A transaction
  between the two limits is admitted and can never be placed.
- **Canonical nonce encoding.** `TxValidatorNonceEncodingValidator` refuses a nonce with
  leading zeros; rustock decodes it leniently (`crates/core/src/rlp_compat.rs`) and admits it,
  keyed by the raw hash while the sender cache uses the re-encoded one.
- **Free bridge transactions.** Before `areBridgeTxsPaid`, a federator's call to the Bridge
  with gas limit 0 costs nothing (`TxValidatorAccountBalanceValidatorTest.balanceIsNotValidatedIfFreeTx`);
  rustock's pool checks balance and intrinsic gas unconditionally. Regtest and custom chains
  only.

Also, `account_slots = 0` is accepted by the CLI and then refuses every transaction as
`NonceTooHigh`; rskj throws at construction
(`TxValidatorNonceRangeValidatorTest.illegalAccountSlotsValue_Zero`).

## Fix

Add the four steps in `validate_tx`, in rskj's order, and reject a zero `account_slots` at
startup. Port the `co.rsk.net.handler.txvalidator` tests the parity table marks as gaps.

## Status

Fixed on 2026-10-30, rustock branch `fix/miner-gas-packing-cap-and-gasprice-gate`. The pool
takes `ChainRules` (the hardfork ladder, the free Bridge senders, the sequential sublist
minimum, the RSKIP252 height), which the node builds from its chain config, and `validate_tx`
now follows `TxPendingValidator` step by step: the gas limit is bounded by the larger sublist
once RSKIP351 and RSKIP144 are active, a free Bridge transaction skips the balance check and
costs no intrinsic gas (also in the pending-plus-new cost, rskj's `getTxBaseCost`), and a price
over 80 times the block minimum is refused from RSKIP252 on. A nonce with leading zeros or
more than eight bytes is refused on the raw bytes before decoding. `account_slots` under 1 is
refused at the flag and at pool construction. Tests ported: the two
`TxValidatorMaximumGasPriceValidatorTest` cases, `validateNonceEncoding` case for case plus an
on-the-wire test, `balanceIsNotValidatedIfFreeTx`, `validIntrinsicGasPrice`'s free case,
`illegalAccountSlotsValue_Zero`, and a sublist-bound test for `TxPendingValidator`.
