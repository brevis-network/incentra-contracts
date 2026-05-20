# `BatchExecutor` — when (not) to use it

`BatchExecutor` is a minimal EIP-7702 batch executor that lets an EOA atomically
perform a sequence of plain `CALL`s in one transaction. In this repo its sole
intended use is operator-side reward funding: a funding EOA sends N
`token.transfer(claimContract, amount)` calls — possibly across different
reward tokens and different campaign contracts — in a single tx.

## This is a fallback path, not the default

Use `BatchExecutor` **only when the operator's wallet cannot batch transactions
natively**. If batching is already available via the wallet or account
abstraction in use, prefer that path — it is better audited, better tooled, and
avoids attaching delegated code to the operator EOA.

Prefer the native option when any of the following applies:

- **Smart-contract wallet / multisig (Safe, etc.)** — submit a `MultiSend` /
  multicall transaction directly.
- **ERC-4337 account abstraction wallet** — pack multiple calls into one
  `UserOperation` `callData`.
- **Wallet UI with native batching** — e.g. a wallet that already exposes
  "send multiple" / EIP-5792 `wallet_sendCalls`, or its own EIP-7702 delegation
  to an audited batcher. Use the wallet's built-in flow.

Only fall back to `BatchExecutor` when:

- The funding signer is a plain EOA, **and**
- The wallet does not natively batch, **and**
- The chain supports EIP-7702 (type-4 authorizations).

For a single transfer, do not use `BatchExecutor` — just send a normal
`token.transfer` tx.

## Usage shape (self-sponsored only)

`BatchExecutor.execute` requires `msg.sender == address(this)`. Under EIP-7702
this means the delegating EOA must be the transaction sender — the EOA signs
both the type-4 authorization and the outer transaction. **Relayer / sponsor
flows are deliberately not supported.** Supporting them safely requires a
signature-plus-nonce scheme that this contract intentionally omits; if you need
a sponsor, use a different batcher.

Typical operator flow:

1. Operator EOA signs a type-4 authorization delegating its code to a deployed
   `BatchExecutor`.
2. Operator EOA sends a tx to itself calling
   `execute(Call[] calldata calls)` with the funding payload.
3. Each `Call` is `{ target, value, data }`; for ERC-20 funding, `target` is
   the token, `value` is 0, and `data` is `transfer(claimContract, amount)`.
4. Any inner call failure reverts the whole batch (`CallFailed(index, ret)`).

Per-tx delegation is the recommended deployment mode — the contract holds no
state across transactions, so there is no reason to leave the delegation
attached to the EOA beyond the funding tx.

## What `BatchExecutor` does not do

- It does **not** custody tokens or ETH. Tokens transferred during a batch
  move directly from the EOA's balance.
- It does **not** validate targets, recipients, or amounts. Pre-tx checks
  (balances, correct claim-contract addresses, correct decimals) remain the
  operator's responsibility.
- It does **not** support partial success — atomic all-or-nothing only.
- It does **not** accept calls from any sender other than the EOA itself.

See `BatchExecutor.sol` for the full security properties and `test/lib/BatchExecutor.t.sol`
for the behaviors that are verified.
