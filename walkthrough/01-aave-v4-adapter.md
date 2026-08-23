# Checkpoint 1 · `AaveV4Adapter` — reading what you already have

> Part of the riya guided build. Nothing to write in this checkpoint — the
> contract already exists at `src/adapters/AaveV4Adapter.sol`. Everything
> downstream is shaped by decisions inside it, so start here.

---

## What it's for

One sentence: **it turns Aave's silently-growing balance into discrete events
Creditcoin can prove.**

That's the whole job, and it's subtler than it sounds. Aave positions *rebase* —
your balance grows every block with no transaction and no log. Attestcoin
readability can only prove **transactions and events**. It cannot prove state. So
there is no way to prove "the position is now worth $1,050."

The adapter's answer: periodically pull the profit out in a real transaction, and
emit your own event describing it. Continuous yield becomes a sequence of
discrete, provable facts.

That conversion is why riya needs a contract on Ethereum at all, instead of just
pointing at the user's own Aave position.

---

## Where it sits

```
USDC ──▶ RiyaEscrow ──▶ AaveV4Adapter ──▶ Aave V4 Spoke
         (custody)      (strategy)
```

It has exactly one privileged caller, the escrow, which it calls `i_vault`. It
never learns Creditcoin exists.

---

## State — and why the split matters

Five immutables, one mutable:

| Variable | Why |
|---|---|
| `i_vault` | The only address allowed to move principal. Set once, no owner, no setter. |
| `i_spoke` | Aave V4 replaced V3's `Pool` with a `Spoke` that routes to a liquidity `Hub`. |
| `i_reserveId` | V4 addresses a market by **numeric id**, not by the underlying's address. This is the big API change from V3. |
| `i_asset` | Read back *from the Spoke* at construction, not passed in. |
| `i_minHarvest` | Smallest harvest worth paying Ethereum gas for. |
| `s_principal` | Assets supplied that are principal, **not** yield. |

Two of those deserve a pause.

### `i_asset` is derived, not supplied

The constructor does:

```solidity
i_asset = IERC20(spoke.getReserve(reserveId).underlying);
```

`getReserve` reverts if the reserve isn't listed — so a typo'd `reserveId` fails
at *deployment* rather than sitting there silently paired with the wrong token.
You cannot deploy this contract in an inconsistent state.

That's a pattern worth stealing generally: **derive what you can derive, so
there's no second field to get wrong.**

### `s_principal` is the entire yield measurement

There's no oracle and no index maths anywhere in riya. Yield is defined as one
subtraction:

```
yield = (what Aave holds for us) − (what we put in)
```

`s_principal` is the right-hand term. Every correctness question about riya's
yield accounting reduces to "is `s_principal` right?"

---

## The functions

### `deposit(uint256 amount) external onlyVault returns (uint256 assets)`

Pull `amount` from the vault, hand it to Aave, record it as principal.

The order is:

1. `safeTransferFrom(i_vault, address(this), amount)`
2. `forceApprove(address(i_spoke), amount)`
3. `spoke.supply(i_reserveId, amount, address(this))`
4. `s_principal += assets`

Two details:

- It credits **`assets`** — what Aave *reported* it took — not the `amount`
  argument. Those can differ (fee-on-transfer tokens, rounding). Trusting the
  number the external protocol hands back, rather than the one you asked for, is
  the safer habit.
- `forceApprove` rather than `approve`, because some tokens (USDT, famously)
  revert if you set a non-zero allowance over a non-zero one. `forceApprove`
  zeroes first.

### `withdraw(uint256 amount, address to) external onlyVault returns (uint256 assets)`

Pull principal back out. **This function has no caller in v1** — it's
`onlyVault`, and the escrow never calls it.

That's deliberate, and worth understanding rather than "fixing." Releasing
collateral back to a user on Ethereum would require Creditcoin to send a message
*out* to Ethereum — writability — which isn't released. So v1 collateral is
locked.

The temptation is to add an owner-gated escape hatch. **Don't.** An owner who can
drain the vault is precisely the rug vector a judge looks for, and the lock is
what makes the design safe in the first place: a user who could withdraw would
pull their money and keep the loan.

One line inside is subtle:

```solidity
s_principal = assets < principal ? principal - assets : 0;
```

Aave treats "an amount above the max withdrawable" as a full exit. So passing
`type(uint256).max` takes the yield with it, and `assets` can exceed
`s_principal`. Without the clamp that's an underflow revert, and the position is
permanently stuck.

### `harvest() external returns (uint256 assets)` ← the important one

Permissionless. Anyone may pay the gas to retire someone else's debt, because the
yield can only ever go to one place — the vault.

```solidity
uint256 available = yieldAccrued();
if (available < i_minHarvest) revert ...;

(, assets) = i_spoke.withdraw(i_reserveId, available, address(this));
i_asset.safeTransfer(i_vault, assets);   // ← money moves

emit Harvested(msg.sender, assets);      // ← THEN the event
```

**The event fires after the transfer, and that ordering is the foundation of the
entire security model.**

Here's why. Checkpoint 6 will show that the ASC on Creditcoin proves a
transaction and reads `Harvested` out of its logs. If the event were emitted
*before* the transfer and the transfer then failed, the whole transaction reverts
and the log never lands — fine. But if the emit came first and someone later
restructured the function so a transfer failure could be swallowed, Creditcoin
would credit yield that never arrived and mint debt relief against nothing.

By emitting last, the invariant is structural:

> **If the log exists in a successful transaction, the money moved.**

The proof and the value travel together. You'll see this rule again at checkpoint
6 as the `receiptStatus == 1` check, and the two together are what let Creditcoin
trust a number it can't independently see.

#### On `i_minHarvest`

Mainnet gas is real. The only lever against it is harvesting less often in bigger
batches — never "use a cheaper chain," since Ethereum is the only permitted
source chain. It's immutable and per-deployment rather than hardcoded because the
right floor depends on the asset's decimals and the gas environment.

### `totalAssets()` and `yieldAccrued()` — public views

```solidity
function yieldAccrued() public view returns (uint256) {
    uint256 total = totalAssets();
    uint256 principal = s_principal;
    return total > principal ? total - principal : 0;
}
```

The clamp handles an Aave reserve carrying a deficit — the position reports
*less* than principal. That isn't a negative harvest, it's a loss. Returning 0
means `harvest()` simply reverts on the minimum check rather than underflowing.

Follow that scenario downstream, because it's riya's honest risk: **if Aave is
hacked or the reserve is impaired, the collateral shrinks but the Creditcoin debt
doesn't.** riya never liquidates, so the protocol absorbs it. `edge_case.md` says
to name this in the submission yourself. Judges respect a risk you surface before
they find it.

---

## Why `IAaveV4Spoke` is hand-written

`src/interfaces/IAaveV4Spoke.sol` mirrors four functions from Aave's real
`ISpoke` instead of importing it. The reason is in its NatSpec: Aave V4 imports
its own tree with root-absolute `src/...` paths. The compiler can resolve those
with a context remapping, but `forge lint` cannot — so importing their sources
directly costs you the linter across the whole project.

The tradeoff is that the mirror can drift. It's pinned to
`aave/aave-v4 @ v0.5.11`, and the `Reserve` struct's field layout is the fragile
part, since it's ABI-decoded positionally. **Move the pin, re-check that struct.**

---

## What to test later (checkpoint 9)

- `withdraw` reverts for a non-vault caller.
- `harvest` below `i_minHarvest` reverts with the right two values.
- Constructor reverts on an unlisted `reserveId`.
- Full exit via `type(uint256).max` doesn't underflow `s_principal`.
- After `deposit(1000)` then simulated growth to `1050`: `yieldAccrued() == 50`,
  and post-harvest `s_principal` is still `1000` while the escrow's balance rose
  by 50.

That last one is the load-bearing invariant: **`harvest` must not change
`s_principal`.** It withdraws only the excess, so principal is untouched by
construction — but a test should pin it, because it's the assumption every later
contract inherits.

---

## Questions to sit with

- Does the permissionless `harvest()` bother you? Who actually calls it in
  production, and what happens if nobody does?
- Would you have derived `i_asset` from the Spoke, or passed it into the
  constructor? What does each choice make impossible?

**Next:** Checkpoint 2 — `IYieldAdapter`, the seam between the escrow and the
strategy.
