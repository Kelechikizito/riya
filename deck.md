# Riya — Pitch Deck

*13 slides. Headline, body, speaker note. Paste into a Google Doc as-is; each slide maps
one-to-one onto a slide when you move it to Slides.*

---

## SLIDE 1 — TITLE

# Riya

### Self-repaying loans, across two chains

Your dollars earn on Ethereum. Your loan lives on Creditcoin.
The yield repays the debt. You never make a payment.

`Creditcoin Hackathon · Built on the Block Prover Precompile 0x0FD2`

> **Speaker note:** Don't explain anything yet. Read the second line and stop.
> The whole pitch is in it.

---

## SLIDE 2 — THE PROBLEM

### Self-repaying loans work. They just can't leave one chain.

- Alchemix proved the model: deposit collateral, borrow against it, let the yield retire
  the debt while you do nothing.
- It only works where the lender can **see** the yield arrive.
- A contract on Creditcoin cannot see an Ethereum transaction.
- Today that gap is closed by bridges and oracles — a multisig, a committee, a price feed.
  **Every one of them is a party that can lie, stall, or be drained.**

**So the yield stays on the chain that earns it, and the credit exists nowhere.**

> **Speaker note:** Land "a party that can lie, stall, or be drained." That sentence is
> the reason this project exists.

---

## SLIDE 3 — THE INSIGHT

### Creditcoin can read Ethereum natively. So the loan can too.

- Attestcoin's Block Prover Precompile lets a Creditcoin contract verify that an Ethereum
  transaction really happened — **checked by the chain, not attested by a committee.**
- That turns "my collateral earned $85 last week" from a claim into a **fact a contract
  can act on**.
- Once the loan can see the yield, it can retire itself.

**No bridge. No oracle. No trusted relayer.**

> **Speaker note:** This is the hinge of the pitch. Everything before is the problem,
> everything after is the consequence.

---

## SLIDE 4 — HOW IT WORKS

### One deposit. Six steps. Zero repayments.

Ada has $1,000 of USDC and wants cash without selling.

1. **Deposits** $1,000 → `RiyaEscrow` on Ethereum → straight into Aave V4
2. **The deposit is proven** — a worker submits an inclusion proof, Creditcoin re-checks
   the Ethereum block itself via `0x0FD2`
3. **Borrows $100** — new addresses open at a 10% limit, and mint rUSD on Creditcoin
4. **The position earns** — Aave pays ~5%/yr; `harvest()` turns silent rebasing into a
   discrete, provable transaction
5. **Each harvest is proven and retires debt** — Creditcoin verifies it the same way,
   takes 15%, spreads the rest across open positions
6. **The debt reaches zero** — Ada never repaid a cent

`[DIAGRAM: Ethereum (money) ——— proof ———> Creditcoin (decisions). One arrow, one direction.]`

> **Speaker note:** Say "only a proof crossed" while the diagram is up. No tokens move
> between chains — that's what makes it not a bridge.

---

## SLIDE 5 — WHY THIS CAN ONLY BE BUILT ON CREDITCOIN

### Take the precompile away and the product stops existing.

| | |
| --- | --- |
| **Verified by the chain** | Creditcoin re-runs the Ethereum inclusion check itself |
| **One copy of the accounting** | Ethereum holds money and states facts; Creditcoin decides what they mean. No mirrored state to drift |
| **The destination is the point** | rUSD is a plain ERC-20 on Creditcoin. The position never needs to leave |
| **Nothing waits on writability** | Every proof travels inbound. The outbound leg is still in audit, and we don't need it |

**The test for any cross-chain design: would it still work, unchanged, on another L2?
Riya answers no — four times.**

> **Speaker note:** This is the Technical Alignment slide. If a judge only remembers one
> slide, make it this one.

---

## SLIDE 6 — THE SECURITY MODEL

### The precompile answers one question. We ask three more.

It tells you a transaction is in a real block. It does **not** tell you the transaction
succeeded, that you haven't already acted on it, or who emitted the logs inside it.

| Check we add | The attack it closes |
| --- | --- |
| Replay key — chain + height + root + tx index | Replaying one real harvest until every borrower's debt hits zero |
| `receiptStatus == 1` | A reverted transaction still sits in a block and still proves cleanly |
| `log.address_` pinned per event | Anyone can deploy a contract emitting `TokensHarvested` worth one billion |

**Drop any one of the three and the protocol is drainable.**

> **Speaker note:** Most submissions call the precompile and trust the answer. This slide
> is the difference between integrating and understanding.

---

## SLIDE 7 — WE ATTACK OUR OWN PROTOCOL

### Forged event. Genuine proof. Rejected anyway.

- Event signatures are public. Anyone can emit `TokensHarvested` with a value of one
  billion dollars.
- They can then obtain a **completely valid** Attestcoin proof for it — the transaction
  is real, it succeeded, the log is genuinely in that block.
- **Every cryptographic check passes.**
- `make attack` does this on live Sepolia and carries the proof to our contract.

**Rejected on `log.address_` — the one field a forger cannot control.**

> **Speaker note:** Run this live if you have 90 seconds. Nothing else in the deck
> converts skeptics as fast as watching a valid proof get refused.

---

## SLIDE 8 — IT IS LIVE

### Two chains. Thirteen proofs. Real debt retired.

| | |
| --- | --- |
| Total collateral | **$5,100** |
| Debt retired by proven yield | **$300.00** |
| Credit score | **30** — up from 0 |
| Borrow limit | **20%** — one tier up the ladder |
| Proofs verified on Creditcoin | **13** (6 deposits, 7 harvests) |

Deployed on Creditcoin Testnet and Ethereum Sepolia. Every address and transaction is on
a public explorer.

**The credit score is not a mock. It moved because proven yield retired real debt.**

> **Speaker note:** Have the explorer open in a tab. Offer to click into any row — the
> offer matters more than whether they take it.

---

## SLIDE 9 — THE CREDIT SCORE

### A limit you earn, not one you buy.

- Borrowing starts at **10%** of collateral and climbs to **50%**.
- The score moves for exactly one reason: **yield retiring your debt.**
- **Cash repayment does not count.** Borrow $100, repay $100 on a loop, and your score
  stays at zero.
- So the ladder measures **productive collateral** — the only thing worth extending
  credit against.

**This is a credit primitive other Creditcoin protocols can read and price against.**

> **Speaker note:** The anti-gaming property is the part people don't expect. Say the
> borrow-repay loop out loud and then say "that buys you nothing."

---

## SLIDE 10 — BUSINESS MODEL

### 15% of yield. Paid by the yield, not by the user.

- Every harvest is split: **85% retires borrower debt, 15% is protocol revenue.**
- At $5,100 of collateral we have already accrued **$105** in fees on testnet.
- The user never writes a cheque — the fee comes out of money their own collateral earned.
- Revenue scales with TVL and with yield, not with transaction count.

**Honest note:** fees currently accrue as a claim on USDC held in the Ethereum escrow.
Collecting them means minting the fee as rUSD against the margin that already backs it —
a change that needs no new protocol capability.

> **Speaker note:** Volunteer the honest note. A judge who finds it themselves discounts
> everything else; a judge who hears it from you trusts the rest.

---

## SLIDE 11 — ROADMAP

### Phases 0–2 need nothing that doesn't exist today.

| Phase | | |
| --- | --- | --- |
| **0 — Shipped** | The vertical slice | USDC → Aave V4 → proofs → rUSD against a credit ladder |
| **1 — Next** | Harden and open | Audit, batched harvests tuned to mainnet gas, permissionless watchers, more assets behind `IYieldAdapter` |
| **2 — Ecosystem** | Make rUSD worth holding | DEX liquidity, the credit score as a public primitive, delegated borrowing, merchant rails |
| **3 — Gated** | The return leg | Collateral release to Ethereum and additional source chains — **blocked on Creditcoin writability, not on us** |

> **Speaker note:** Phase 3 being labelled as blocked is the point. It says we read the
> docs and didn't put anything unavailable on the critical path.

---

## SLIDE 12 — WHAT WE KNOW IS WRONG

### Three limitations, stated before you ask.

- **If Aave is impaired, the protocol absorbs it.** Yield is holdings minus principal.
  If the reserve takes a loss, collateral shrinks while the debt does not, and there is
  no liquidation path. *Designed answer: prove the shortfall inbound the same way yield
  is proven, absorb it from accrued fees, socialise the remainder.*
- **Protocol fees accrue but cannot yet be collected.** A claim on USDC in the Ethereum
  escrow. *Fix needs no writability — mint the fee as rUSD.*
- **Proofs are not instant.** Three to four minutes on testnet, because Creditcoin must
  attest the Ethereum block first. **That latency is the honest cost of not trusting a
  bridge.**

> **Speaker note:** This slide wins more points than it loses. A risk a judge finds
> alone discounts the whole deck; a risk you name first buys credit for everything else.

---

## SLIDE 13 — EXECUTION

### Built, tested, deployed, and adversarially demonstrated.

- **179 tests across 15 suites** — fuzz suites state properties, not examples:
  *settling twice changes nothing; a deposit never raises the score; no impostor can
  create collateral.*
- **10 tests run against live Creditcoin Testnet**, failing if the chain registry
  disagrees with our constants.
- **The Aave adapter is tested against real Aave V4** on an Ethereum Mainnet fork.
- **Reproducible deploy** — circular constructor pins predicted with
  `vm.computeCreateAddress` and each prediction asserted before it is trusted.
- Off-chain worker with dead-lettering and a replay key pinned to the contract's by test.

**Code:** github.com/Kelechikizito/riya

> **Speaker note:** Close on the test properties, not the count. "Settling twice changes
> nothing" tells them more about the engineering than any coverage number.

---

## APPENDIX — NUMBERS TO REFRESH BEFORE PRESENTING

Run `make position` and update slides 8 and 10 if you demo again first.

| Field | Current | Source |
| --- | --- | --- |
| Total collateral | $5,100 | `s_totalCollateral` |
| Debt retired | $300.00 | `s_repaidByYield` |
| Credit score | 30 | `score(address)` |
| Borrow limit | 20% | `maxLtvBps(address)` |
| Protocol fees | $105.00 | `s_protocolFees` |
| Proofs verified | 13 | worker store |
