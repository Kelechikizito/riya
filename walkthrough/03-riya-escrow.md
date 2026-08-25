# Checkpoint 3 · `RiyaEscrow` — custody only

> Part of the riya guided build. File to create:
> `src/source-chain/ethereum/RiyaEscrow.sol`.
>
> The first contract written from nothing. About 40 lines, and deliberately,
> aggressively boring.

---

## The job

Take USDC. Hand it to the adapter. Emit one event. That is all.

The temptation is to make it a vault — shares, `totalAssets()`, withdrawals,
ERC-4626. Resist it, and know why:

> **Every one of those is a second copy of accounting that already exists on
> Creditcoin. Two copies can drift. One cannot.**

Deleting the Ethereum half removes the desync bug class outright rather than
guarding against it.

---

## The shape

```solidity
contract RiyaEscrow {
    error RiyaEscrow__BelowMinDeposit(uint256 provided, uint256 minimum);
    error RiyaEscrow__ZeroAddress();

    IERC20        public immutable I_ASSET;
    IYieldAdapter public immutable I_ADAPTER;
    uint256       public immutable I_MIN_DEPOSIT;

    event Deposited(address indexed user, uint256 assets);

    constructor(IYieldAdapter adapter, uint256 minDeposit);

    function deposit(uint256 assets) external;
}
```

**One function. One event. No mutable state at all.**

### What "no mutable state" buys you

`s_` variables: zero. Which means:

- **No reentrancy guard needed.** Reentrancy corrupts state by re-entering
  between a check and a write. There is no state to corrupt — re-entering
  `deposit()` merely performs another honest deposit. Adding `nonReentrant` here
  would be cargo-cult: ~2,900 gas to protect nothing.

  Contrast the adapter, which *does* have `s_principal`, so its guard earns its
  place. Know the difference between a guard that works and a guard that
  signals diligence.

- **No owner, no admin, no pause.** Nothing to govern.
- **Nothing to read from it.** The only interesting number — everyone's
  collateral — lives on Creditcoin.

---

## `deposit(uint256 assets)` — the logic

```
CHECKS
  assets >= I_MIN_DEPOSIT, else revert

INTERACTIONS
  I_ASSET.safeTransferFrom(msg.sender, address(this), assets)   // user → escrow
  I_ASSET.forceApprove(address(I_ADAPTER), assets)              // permit the pull
  I_ADAPTER.deposit(assets)                                     // escrow → adapter → Aave

  emit Deposited(msg.sender, assets)                            // money moved first
```

### Why two hops instead of one

The money moves user → escrow → adapter. You could imagine the user approving the
adapter directly and saving a transfer. You cannot: the adapter's `_deposit` does
`safeTransferFrom(I_ESCROW, ...)` — it pulls specifically from the vault, and it
is `onlyEscrow`.

That is not an accident. **The escrow is the custody boundary**, and custody
boundaries are worth one extra transfer.

### The emit is last, again

Same rule as `harvest()`: if the log exists in a successful transaction, the
money moved. Here it is structurally guaranteed anyway — a failed transfer
reverts the whole call — but keeping the ordering uniform means you never have to
reason about it per-function.

### There is no EFFECTS step

Write the CEI banners if you like them, but notice the middle one is empty. That
is the contract telling you it has no state.

---

## The idle balance is the protocol reserve

After a deposit the escrow holds **zero** — everything is forwarded. But
`harvest()` sends yield *to the escrow*, and the escrow has no function that can
move it out.

So over time:

```
I_ASSET.balanceOf(escrow)  ==  every dollar of yield ever harvested
```

Permanently stuck, by design. That is the bad-debt backstop and the notional
source of the 15% protocol fee that accrues on Creditcoin.

### Name the cost honestly — a judge will ask

Harvested yield **stops earning**. Alchemix would re-supply it to compound.

You cannot here without breaking the 1:1 mapping: re-depositing would grow
`s_principal`, which would turn yield into principal, and Creditcoin's collateral
figure would no longer match the dollars actually escrowed.

v1 accepts the drag. Compounding goes in the roadmap alongside withdrawals.

---

## Why `I_MIN_DEPOSIT` exists — not the reason you would guess

It is not protecting the escrow. It is protecting **your CTC balance on the other
chain.**

Every deposit generates an event your worker must prove: a proof-server request,
plus a Creditcoin transaction whose gas *you* pay. A $0.01 deposit costs you a
full proof. Without a floor, someone dusts you a thousand times and drains the
worker's wallet — a griefing attack on an off-chain budget, executed from another
chain.

Worth understanding as a category:

> **In a cross-chain system, source-chain limits often exist to protect
> destination-chain economics.**

---

## Tests to write

- Deposit below `I_MIN_DEPOSIT` reverts, with both values in the error.
- Deposit without prior approval reverts.
- After a successful deposit: escrow balance is **0**, and the adapter's
  `s_principal` rose by exactly `assets`.
- `Deposited` emitted with the right `user` and `assets`.
- Constructor reverts on a zero adapter.
- **There is no withdraw path** — assert the ABI has no function that moves
  `I_ASSET` out. This is the security model, so pin it with a test.
- Simulate a harvest: escrow balance grows, and nothing can reduce it.

---

## Three decisions before writing it

### 1. Where does `I_ASSET` come from?

Constructor argument, or `I_ADAPTER.asset()`?

Take the derivation, for the reason from checkpoint 1 — otherwise nothing stops a
USDC escrow pointed at a DAI adapter, and nothing complains until the first
deposit. Needs the sixth `IYieldAdapter` signature that was left out.

### 2. Should `Deposited`'s `assets` be indexed?

`research/build-plan.md` leaves it unindexed, so checkpoint 6 reads it via
`abi.decode(log.data, ...)` while harvests come from `topics[2]`. The plan flags
that asymmetry as fine but load-bearing.

Indexing both would make the ASC's two loops identical. Either works —
**whichever you pick, checkpoint 6 must match.**

### 3. `deposit(uint256)` or `deposit(uint256, address recipient)`?

Right now `msg.sender` becomes the Creditcoin account. That is correct for an EOA
— same key, same address on both EVM chains.

It is **not** correct for a smart-contract wallet: a Safe at address X on
Ethereum is not controlled by whoever holds X on Creditcoin. An explicit
recipient costs one parameter and removes the footgun.

v1 can ship without it if the caveat is named in the submission.

---

**Next:** Checkpoint 4 — event design, and exactly what the ASC sees when it
decodes these logs.
