# How value and proofs move through riya

> Written to clear up the most common confusion in this design: **nothing crosses
> between the two chains except proofs.** No bridge. No wrapped token. No
> burn-and-mint of the deposited money.

---

## 1. The actors

Four, and keeping them apart is most of the battle.

| Actor | Where | Writes to | Pays gas in | Job |
|---|---|---|---|---|
| **User** | Ethereum + Creditcoin | both | ETH, CTC | Deposits, borrows, maybe repays |
| **Keeper** | off-chain | **Ethereum** | ETH | Calls `harvest()` |
| **Readability worker** | off-chain | **Creditcoin** | CTC | Proves events to the ASC |
| **ASC** | Creditcoin | Creditcoin | — | Verifies proofs, calls the ledger |

The keeper and the worker are the two people mix up. They can live in one Node
process, but they are two jobs, with two keys, on two chains:

> **The keeper writes on Ethereum. The worker writes on Creditcoin.**
> The worker only ever *reads* Ethereum.

---

## 2. The flows

### Deposit

- **User** calls `escrow.deposit(amount)` — the only contract they ever touch on Ethereum
- **Escrow** pulls the USDC, approves the adapter, calls `adapter.deposit()`
- **Adapter** supplies it to Aave
- Two logs land in **one** transaction — the adapter's first, then the escrow's
- **Worker** sees `TokensDepositedConfirmedByEscrow`, waits for attestation, fetches
  proofs, calls `submit()` on the ASC
- **ASC** verifies, decodes, and credits collateral in `LoanLedger`

### Borrow

- **User** calls `borrow()` on Creditcoin, up to their LTV limit
- `RiyaUSD` is minted to them
- Nothing on Ethereum is involved at all

### Harvest — the core of v1

- **Keeper** calls `adapter.harvest()`
- It polls `yieldAccrued()` for free (a `view`, so no gas) and fires only when the
  figure crosses `I_MIN_HARVEST`. **The threshold is the schedule** — there is no timer
- Yield leaves Aave, lands in the escrow, and *then* `TokensHarvested` fires
- **Worker** proves that transaction to the ASC
- **Ledger** takes the 15% fee and drops every borrower's debt pro-rata

### Withdraw

- **Nobody calls it.** It is `onlyEscrow`, and the escrow has no code path that reaches it
- Deliberate: releasing collateral needs Creditcoin to message Ethereum, which needs
  writability, which is not released
- It exists for phase 2. Test it by pranking the escrow; do not wire it up

---

## 3. Why the escrow needs no "signal" function

A natural question: *the escrow receives the harvested money — where is its function
to announce that?*

There isn't one, and there should not be.

The escrow is **passive** during a harvest. Money arrives; that is all it does.
The event the worker proves comes from the **adapter**:

```
keeper → adapter.harvest()
           withdraw yield from Aave
           transfer it to the escrow          ← escrow does nothing but receive
           emit TokensHarvested(caller, assets)   ← the adapter's own log
```

Adding a signalling function to the escrow would mean the escrow has to *notice* an
incoming transfer. ERC-20 transfers do not notify the recipient, so you would need a
hook or a separate poke transaction — and both create a way for the signal and the
money to disagree.

Letting the adapter announce its own transfer keeps the two inseparable: the transfer
happens on the line above the `emit`, in the same transaction.

**The Ethereum side is functionally complete for v1.** What remains there is tests,
not contracts.

---

## 4. The only two events that matter

| Event | Emitted by | Becomes on Creditcoin |
|---|---|---|
| `TokensDepositedConfirmedByEscrow(user, assets)` | escrow | collateral for that user |
| `TokensHarvested(caller, assets)` | adapter | debt reduction for **everyone** |

Both carry `assets` as an `indexed` parameter, so it arrives in `topics[2]` and the ASC
reads it as `uint256(log.topics[2])` rather than decoding `data`.

Two emitters means two separate trust anchors: a `Deposited` log is believed only from
the escrow's address, a `Harvested` log only from the adapter's. Neither substitutes
for the other.

*(Decoding detail is checkpoint 4; the ASC that does it is checkpoint 6.)*

---

## 5. Nothing is bridged — the part that trips everyone

**The harvested USDC never leaves Ethereum.** It sits in the escrow permanently. What
reaches Creditcoin is a *proof that it arrived* — a cryptographic fact, not value.

```
Ethereum:    $35 of USDC moves Aave → escrow.  Stays there forever.
Creditcoin:  a number goes down.  Alice's debt: $100 → $65.
```

Nothing is minted or burned to make that happen. Debt is a `uint256` in a mapping, and
settling it is subtraction.

> The two chains share a **unit of account** — dollars — not a token.

Alice's real USDC on Ethereum and her loan balance on Creditcoin are separate things
that both happen to be counted in dollars. That is why "does USDC exist on Creditcoin"
turns out not to matter.

### Where minting actually happens

There *is* a token on Creditcoin, `RiyaUSD` — but it is minted when someone **borrows**,
not when yield arrives:

| Action | Token movement |
|---|---|
| Deposit proven | none — collateral is a number |
| **Harvest proven** | **none — debt is decremented** |
| User borrows | `RiyaUSD` minted to them |
| User repays manually | `RiyaUSD` burned |

---

## 6. So what actually retires the debt?

**The number inside the proven event.** `assets` is read from `topics[2]` and passed
straight to `ledger.onHarvest(assets)`.

But what *backs* that reduction is the USDC now sitting in the escrow. Follow one full
round:

```
Alice deposits $1,000    → escrow → Aave.   Escrow holds $0.
Alice borrows $100       → 100 RiyaUSD minted on Creditcoin. She spends it.
Aave earns $35.
Keeper harvests          → $35 leaves Aave, lands in the escrow. Escrow holds $35.
Proof lands              → Alice's debt: $100 → $65.
```

| | Ethereum | Creditcoin |
|---|---|---|
| before harvest | escrow $0, Aave $1,035 | debt $100 |
| after harvest | escrow **$35**, Aave $1,000 | debt **$65** |

**Alice paid the $35.** It was her yield, earned on her deposit, and it is now locked in
the escrow where she can never reach it. The protocol received $35 of real value and
cancelled $35 of her obligation. Those balance exactly.

The $35 did not vanish and did not travel. It moved from "Alice's yield" to "the
protocol's reserve", and Creditcoin learned that it had.

**The escrow's growing balance is the backing for every dollar of debt ever forgiven.**

### Two consequences

- **The borrower never repays — they forgo.** They give up yield instead of handing over
  cash. That is the Alchemix idea, and it is why manual repayment deliberately does not
  raise the credit score: paying cash is not the behaviour being rewarded.
- **The 15% fee is a claim on that escrow balance**, accrued as a number on Creditcoin.
  It becomes real money only in phase 2, when withdrawals exist. Until then it is
  bookkeeping against a pot nobody can open.

---

## 7. Access control, in one picture

Two locks, one behind the other:

```
proof → ASC ──(only the ASC)──▶ LoanLedger ──(only the ledger)──▶ RiyaUSD.mint()
```

- **Only the ASC** may call `ledger.onDeposit()` and `ledger.onHarvest()`. Those create
  collateral and retire debt, so they must only ever run behind a verified proof.
- **Only the ledger** may call `riyaUSD.mint()` / `burnFrom()`. So tokens cannot appear
  except through a borrow that passed the LTV check.

*(Checkpoint 7 builds `RiyaUSD`; checkpoint 8 builds `LoanLedger` and both locks.)*

---

## In one paragraph

Users park USDC on Ethereum, where it earns Aave yield. A keeper periodically pulls that
yield into the escrow and the adapter announces it. A readability worker proves that
announcement to Creditcoin, where a ledger — the only place any decision is made —
credits collateral, retires debt, and moves credit scores. The money stays on Ethereum;
only proofs travel. Never leaving is the feature, not the limitation.
