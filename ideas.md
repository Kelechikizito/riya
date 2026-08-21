# What I'm Building — A Loan That Pays Itself Off

Plain-English version. The full reasoning is in `ideas-analysis.md`; this file is
the build spec.

---

## The one-sentence pitch

**You put money to work on Ethereum. You borrow against it on Creditcoin. The
profits your money earns on Ethereum pay off the loan for you, automatically,
until you owe nothing.**

You never make a repayment. You never get liquidated. You just wait.

This is a copy of [Alchemix](https://alchemix.fi), which already proved the idea
works. The new part is that the savings live on **one** chain and the loan lives
on **another**, and Creditcoin can prove what happened on the first chain without
trusting anybody.

---

## How it works, with real numbers

Say Ada has $1,000 of USDC and wants cash now without selling.

1. **Ada deposits.** She puts $1,000 USDC into *our* contract on Ethereum. That
   contract parks the money in Aave, where it earns roughly 5% a year.
2. **We prove the deposit.** Our off-chain bot notices the deposit and asks
   Creditcoin to verify it. Creditcoin checks the maths itself and confirms:
   *yes, that deposit really happened on Ethereum.*
3. **Ada borrows.** Our contract on Creditcoin lends her $500 — half of what she
   deposited. She now has spendable money on Creditcoin and a $500 debt.
4. **The money earns.** Ada's $1,000 sits in Aave making about $50 a year.
   Every so often we "harvest" that profit into our Ethereum contract.
5. **Each harvest is proven and wipes out debt.** We prove each harvest to
   Creditcoin the same way as step 2. Creditcoin sees "$25 of real yield
   arrived" and knocks $25 off Ada's debt. No payment from Ada.
6. **Eventually the debt hits zero.** $500 debt ÷ $50 a year ≈ 10 years. Then
   Ada owes nothing and her $1,000 is hers again.

Ada never repaid a penny. Her savings did it.

### Why she can't get liquidated

She borrowed $500 against $1,000. Her debt only ever goes **down** — nothing in
the system can make it grow. So she can never owe more than she deposited. There
is no margin call, no liquidation, no one seizing her money.

**This is the single most important property of the whole design.** Everything
else in this document flows from it (see "Why this idea works on Creditcoin").

---

## The four things I have to build

This is the standard Creditcoin app shape from `notes.md`. Four pieces:

| # | Piece | Where it lives | What it does |
|---|---|---|---|
| 1 | **Vault contract** | Ethereum / Base | Takes Ada's deposit, puts it in Aave, harvests profit. Shouts (emits an event) every time something happens. |
| 2 | **ASC** (Attestcoin Smart Contract) | Creditcoin | The bouncer. Receives proofs, asks Creditcoin's built-in prover "is this real?", and only then lets anything happen. |
| 3 | **Loan contract** | Creditcoin | The ledger. Tracks who deposited what, who owes what, and hands out loans. Only listens to the ASC. |
| 4 | **Watcher bot** | Off-chain (a script) | Watches Ethereum for our events, fetches the proofs, and hands them to the ASC. Just plumbing — no trust, no power. |

**Flow:** something happens on Ethereum → bot spots it → bot gets proofs → bot
gives them to the ASC → ASC verifies → loan contract updates Ada's balance.

The bot can lie or vanish and **nothing bad happens** — it can't fake a proof.
Worst case, updates stop until we restart it.

### The magic bit

Piece 2 calls a built-in Creditcoin function at address `0x0FD2`. You hand it a
transaction plus two proofs and it answers, in the same transaction, "real" or
"fake". No oracle, no waiting, no committee to trust.

**On any other chain this app is impossible without a bridge.** That's the whole
reason we're on Creditcoin, and it's what the judges are scoring.

---

## Two rules I must not break

### Rule 1: Real money has to arrive. A receipt is not money.

This is the one that could quietly make the protocol bankrupt.

Tempting shortcut: prove "Aave says Ada earned $25" and knock $25 off her debt.
**Don't.** That's cancelling real debt against a number on a screen. The $25 has
to actually land in our Ethereum vault contract *before* we prove anything. We
prove the **harvest transaction that moved the money**, not a yield figure.

Rule of thumb: *the proof and the value travel together, or the lender eats the
loss.* A DeFi-savvy judge will poke at exactly this.

### Rule 2: Every proof gets used once

If someone submits the same valid harvest proof twice, debt gets wiped twice for
free. Every proven transaction hash goes in a `mapping(bytes32 => bool)` and gets
rejected on the second attempt.

Also: Creditcoin's prover only tells you a transaction **was included in a
block** — not that it succeeded. A failed transaction is still "included". Check
the receipt `status == 1` yourself, every time. This is already noted at the top
of `src/ASC.sol`.

---

## Why this idea works on Creditcoin (and the other ideas didn't)

Creditcoin can currently only **read** other chains, not write to them. Proof can
flow *in* to Creditcoin. Nothing can flow back *out*. That killed five other
ideas — see `ideas-analysis.md`.

It doesn't kill this one, and here's the exact reason:

- **No liquidations means no reaching back out.** Every other lending product
  eventually has to seize collateral. Collateral is on Ethereum, the decision is
  on Creditcoin — that needs writing outward, which we can't do. We never have to,
  because Ada can never fall behind.
- **Slow is fine.** Creditcoin deliberately lags a bit behind Ethereum's latest
  block so it never trusts a block that gets reversed. Irrelevant here — this
  plays out over months. There's no price to check in a hurry.
- **The proof is doing real work.** Nobody would lie about an interest rate. But
  "$25 of real yield arrived" is a claim someone would absolutely fake to erase
  debt they never paid. That's a fact worth proving — so the proof isn't
  decoration.

**The one thing still blocked:** giving Ada her $1,000 back at the end. Her money
is on Ethereum; the "she's paid off" decision is on Creditcoin. That's writing
outward, so it's out of scope. It's the *last* step, not the loop — everything
interesting still works and demos fine. Say so openly in the submission.

---

## What the demo shows

One chain (Sepolia), one asset, one yield source. On screen:

1. Ada deposits into the Ethereum vault.
2. The proof lands on Creditcoin — show the actual verification transaction.
3. Ada's loan appears on Creditcoin. She has money.
4. Two or three harvests get proven. **The debt visibly drops each time.**
5. Debt hits zero.

Step 4 is the money shot. That's the bit no other chain can do.

Frontend goes in the existing `frontend/` app: her debt falling, next to the list
of proven harvests that caused it.

### The honesty problem

Ten years of yield doesn't fit in a three-minute demo. So we speed it up — our
own yield source with a silly-high rate, or hand-triggered harvests.

**Say this out loud in the demo.** "We've compressed the timeline; here's the
real rate." A judge who catches hidden time-compression stops believing anything
else you showed. A builder who flags it first looks careful.

---

## Decisions I still need to make

1. **What does Ada actually borrow?** Simplest is an existing Creditcoin token
   the loan contract holds. Minting our own dollar-pegged token (like Alchemix's
   alUSD) means keeping it pegged to $1 — that's a whole second project. **Avoid
   for the hackathon.**
2. **Where does the yield come from?** Real Aave on a testnet is credible but
   fiddly and slow. Our own mock yield contract is fast and controllable but must
   be labelled as a mock. Pick one and be upfront.
3. **How much can she borrow?** Alchemix caps around 50%. Start there — it's
   proven, and it's what makes liquidation impossible.
4. **Who triggers the harvest?** Anyone (permissionless, more decentralised) or
   just us (simpler)? For the demo, just us is fine.
5. **What if two people deposit?** Does each get their own vault, or one shared
   pool with shares? **Shared pool is a lot more accounting.** For the hackathon,
   one vault per user.

---

## Why this should win

| What judges want | How we do | Why |
|---|---|---|
| **Fits Creditcoin technically** | Strong | Remove the proving and the protocol goes bankrupt. It's load-bearing, not sprinkled on. Can't be copy-pasted to another L2. |
| **Uses a proven model** | Strong | Alchemix already did this at scale. We're moving a known-good idea to a new chain — exactly what the brief asks for. |
| **Clear product** | Strong | "Your loan pays itself off using profits from another chain." One sentence, no buzzwords, non-experts get it. |
| **Grows the user base** | Good | Alchemix attracted real money from real retail users. Borrowers on Ethereum are a specific group we can name and reach. |
| **Can actually be built** | Good | Four pieces, all small. Bigger than a toy, much smaller than a platform. |

It's the only idea vetted with **no weak score anywhere**.

**Bonus:** every loan we run produces a verified record of someone's borrowing
and repayment across chains — which is exactly the credit-history data the
original credit-score idea needed as input. Build this and phase 2 comes with
real data already in it. That's a strong roadmap story.

---

## Explicitly not building

- Returning collateral on Ethereum (needs writability — out of scope for this
  hackathon, per Gluwa's answer in `qanda.md`)
- Our own stablecoin
- Multiple source chains
- Multiple collateral types
- Shared pooled vaults
- Liquidations (impossible here by design — that's the point)

---

## Glossary

| Term | Plain meaning |
|---|---|
| **Collateral** | The money Ada locks up to be allowed to borrow. |
| **Yield** | Profit her locked money earns by sitting somewhere useful. |
| **Harvest** | Actually collecting that profit and moving it into our contract. |
| **Source chain** | Where the money is (Ethereum/Base/Sepolia). |
| **ASC** | Our contract on Creditcoin that checks proofs. Attestcoin Smart Contract. |
| **Precompile `0x0FD2`** | Creditcoin's built-in proof checker. Ask it "did this really happen?", get an instant yes/no. |
| **Merkle proof** | Proves a transaction was inside a particular block. |
| **Continuity proof** | Proves that block is really part of Ethereum's history. |
| **Readability** | Creditcoin reading other chains. ✅ Available. |
| **Writability** | Creditcoin acting on other chains. ❌ Not available to us. |
| **Attestation** | Creditcoin's periodic signed snapshot of another chain's state. |
