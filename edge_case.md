# Edge Cases — Self-Repaying Loan

Four questions and their answers. Two of them change what we build.

| # | Question | Short answer |
|---|---|---|
| 1 | What if she pulls her money out of Aave after borrowing? | She can't. We hold it, not her. |
| 2 | Should we add DID / identity checks? | No. There is nothing to protect against yet. |
| 3 | Does USDC exist on Creditcoin? Must tokens match? | No, and no. Nothing crosses but proofs. |
| 4 | How do we know yield was earned? | Aave has no yield event. We make our own. |

---

## 1. She withdraws from Aave after borrowing

**This is the most important question here.** The answer is that it was never her
Aave position.

There are two ways to build this. Only one works.

| Design | What happens |
|---|---|
| **Watch her** — Ada keeps her own Aave position, we just prove it exists | **Broken.** She pulls the money out next block and keeps the loan. |
| **Hold it** — Ada deposits into *our vault*, and the vault supplies to Aave | **Safe.** She has no way to withdraw. |

Our spec already says "she puts $1,000 into *our* contract" — so we are on the
right side. But we never say *why* that matters, and we should. The broken
version is the one people reach for first.

### Why watching can never be patched

Creditcoin proves **transactions and events**, not **current state**.

We can prove "Ada deposited $1,000 at block N."
We cannot prove "Ada still has $1,000."

If she withdraws, nothing tells us. The precompile only sees what someone hands
it, and she will not hand us proof of her own exit. A watcher bot could prove her
withdrawal afterwards and freeze her score — but the money is already gone. That
is a post-mortem, not a safety net.

### So

The vault holds the aTokens. Only the vault can call `withdraw`. Ada's claim is
against our vault, not against Aave.

**Note the irony:** the collateral stays locked even after she repays, because
releasing it needs writability. We already listed that as out of scope. But it is
the *same lock* that makes the design safe. The lock is the security model, not
just a missing feature.

### One risk to name out loud

If Aave is hacked, or the aToken loses its value, the collateral is gone but the
Creditcoin debt remains. We never liquidate, so we absorb the loss. Say this in
the submission. Judges respect a risk you name yourself.

---

## 2. DID / identity before borrowing

**Skip it.** It solves a problem we do not have.

The worry was defaulters and bad actors. But:

- **Nobody can default.** Max 50% LTV, debt only ever goes down, no interest.
  Ada can never owe more than she put in.
- **Many wallets gain nothing.** Ten wallets need ten separate deposits, and each
  gets 10% of its own smaller deposit. Splitting up is worse for the attacker,
  not better. There is no free tier to farm.
- **The real attack is question 1**, and identity does not stop it. Custody does.

It also costs us. It is a whole extra system to build, and a KYC gate sits badly
next to a pitch about financial inclusion.

### Where identity does belong

Phase 3, when we want **undercollateralized** lending — lending more than someone
posts. That is Creditcoin's real thesis. Then default becomes possible and
identity becomes essential.

Good line for the pitch:

> "Collateralized today. The verified repayment record we are building is what
> makes undercollateralized lending possible tomorrow — and that is when identity
> enters."

Say it. Do not build it.

---

## 3. Tokens on Creditcoin

**No USDC on Creditcoin.** Not in Circle's list. What is there: **CTC** (native),
**ATTEST** (the writability fee token in `usc-contracts`), and PenguinSwap
ecosystem tokens.

**The tokens do not need to match, because nothing crosses.**

```
Ethereum:    real USDC  →  our vault  →  Aave     (never leaves Ethereum)
Creditcoin:  our mock USD token, lent to Ada       (never leaves Creditcoin)

                    only PROOFS cross
                    never value
```

There is no bridge here. The two sides share a **unit of account** — dollars —
not a token. Ada's real USDC on Ethereum and her loan tokens on Creditcoin are
separate assets that both happen to be counted in dollars.

That is why our mock token works, and why "which chain has USDC" turns out not to
matter.

---

## 4. How we know yield was earned

**Aave has no yield event.** This surprised me and it is worth knowing.

aTokens **rebase**. The balance in your wallet grows every block on its own. No
transaction. No log. Nothing to prove.

Aave emits `Supply`, `Withdraw`, and `ReserveDataUpdated`. aTokens emit
`Mint`/`Burn` with a `balanceIncrease` field. But those only fire when somebody
interacts, and pulling a yield figure out of index maths across two proven
transactions is fragile.

Add that to "proofs cover events, not state" and reading yield straight from Aave
is a dead end.

### So our vault creates the event

This is the real reason we need our own contract on Ethereum instead of pointing
at Aave:

```solidity
function harvest() external {
    uint256 balance = aToken.balanceOf(address(this));
    uint256 profit  = balance - principal;
    require(profit >= MIN_HARVEST);

    aavePool.withdraw(USDC, profit, address(this));   // value actually moves
    emit Harvested(positionId, profit, nonce++);       // our event, self-describing
}
```

The ASC then proves **that transaction**, filters the logs for our `Harvested`
event, and reads `profit` straight out of it. No index maths. No guessing.
(`EvmV1Decoder` in `usc-contracts` supports filtering logs by event signature.)

### Three things this gets us

1. **Rule 1 is satisfied by design.** The `withdraw` moves real USDC *before* the
   event fires. Proof and value travel together automatically.
2. **The event describes itself.** Amount, position, and nonce are all in the log.
   The ASC never has to reconstruct anything.
3. **Continuous yield becomes discrete facts.** That is the only shape readability
   can consume.

**In one line:** the vault is an *adapter*. It turns Aave's silently growing
balance into events Creditcoin can verify.

---

## What to change in the build

| From | To |
|---|---|
| Custody is implied | Say it plainly: the vault holds the aTokens, Ada cannot withdraw. It is the security model. |
| Yield source is vague | The vault must expose `harvest()` and emit `Harvested(positionId, profit, nonce)`. |
| — | Do not build identity. Put it in the roadmap. |
| — | Do not look for a bridge. Nothing crosses but proofs. |
