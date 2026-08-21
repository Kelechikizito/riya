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
3. **Ada borrows — but only a little at first.** She is brand new, so her credit
   score is **0** and she can borrow **10%** of her deposit: **$100**. She now
   has spendable money on Creditcoin and a $100 debt.
4. **The money earns.** Ada's $1,000 sits in Aave making about $50 a year.
   Every so often we "harvest" that profit into our Ethereum contract.
5. **Each harvest is proven and wipes out debt.** We prove each harvest to
   Creditcoin the same way as step 2. Creditcoin sees "$25 of real yield
   arrived" and knocks $25 off Ada's debt. No payment from Ada.
6. **Repaying raises her score, which raises her limit.** After $40 is retired her
   score is 20 and her limit moves to 20%; after $170 she is at the 50% ceiling.
   See "The credit score" below.
7. **Eventually the debt hits zero.** Then Ada owes nothing — she can redraw at
   her new limit, or walk away with her $1,000.

Ada never repaid a penny. Her savings did it.

### Why she can't get liquidated

She borrowed $100 against $1,000, and she can never borrow more than 50% of it.
Her debt only ever goes **down** — nothing in the system can make it grow. So she
can never owe more than she deposited. There is no margin call, no liquidation,
no one seizing her money.

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

## The credit score — earning a bigger loan

New borrowers start at **10%** and graduate toward a hard ceiling of **50%** by
actually repaying. Nobody gets a full-size loan on day one.

This is the **secured credit card** model — small limit, prove yourself, graduate
— which is about as proven as consumer credit gets, and it puts a *credit
product* at the centre of a submission judged by a credit company.

### The ladder

Score runs **0–100**. (The brief said "0/10" and also "85–100"; reading both as a
0–100 scale, starting at 0.)

| Credit score | Max borrowable |
|---|---|
| 0–19 | 10% |
| 20–39 | 20% |
| 40–59 | 30% |
| 60–84 | 40% |
| **85–100** | **50% — the ceiling, never more** |

### How the score is earned

**Score = 100 × (total dollars ever repaid) ÷ `GRADUATION_TARGET`, capped at 100**,
where `GRADUATION_TARGET` = **20% of your collateral**.

For Ada, 20% of $1,000 is $200, so every $2 of debt retired is one point.

| Ada has repaid | Score | New limit |
|---|---|---|
| $0 | 0 | 10% — $100 |
| $40 | 20 | 20% — $200 |
| $100 | 50 | 30% — $300 |
| **$170** | **85** | **50% — $500** |

### Why the graduation target is a constant, and why it is 20%

**This one number decides whether the demo works.** Make it a named constant, not
a magic number buried in the maths.

The deposit size cannot be used to tune this — the whole system is
scale-invariant. Loan is `D × LTV`, yield is `D × rate`, so time to repay is
`LTV / rate` and **`D` cancels out**. Ada's first loan takes 2 years to
self-repay whether she deposits $100 or $100 million. A minimum deposit does not
make anything faster.

The graduation target is the lever that does:

| `GRADUATION_TARGET` | Repaid to reach score 85 | Years at 5% yield |
|---|---|---|
| 50% of collateral | $425 on $1,000 | 8.5 |
| **20% (chosen)** | **$170** | **3.4** |
| 10% | $85 | 1.7 |

At 50% the ladder is a mortgage and nobody in the demo ever graduates. At 20% it
is a plausible customer journey and the story still holds: *repay a real loan's
worth before you get a real loan.* Tune this constant for the demo rather than
faking anything else.

### Sizing: minimum deposit and minimum harvest

Not for speed — for **unit economics**. Each harvest costs gas on the source chain
to execute and gas on Creditcoin to prove. Below some size the yield being proven
is worth less than the proof of it.

Creditcoin's side is cheap: `notes.md` gives ≈ `2.3e-5 + 2.9e-7 × hash count` CTC,
fractions of a cent for a recently-finalised transaction. **The binding cost is
the harvest transaction on the source chain**, and that is an argument about which
source chain to use:

| Source chain | Harvest gas | Implied minimum deposit |
|---|---|---|
| Ethereum mainnet | a few dollars | ~$4,000 — far too high for a product about inclusion |
| **Base** | cents | **~$100** |

**Use Base.** The spec already said "Ethereum / Base"; this is the argument for
picking one. Cheap gas keeps the minimum small, which keeps the inclusion story
honest.

- **`MIN_DEPOSIT` = $100.** Below this a position cannot generate harvests worth
  proving.
- **`MIN_HARVEST` = $1.** Worth more than the deposit floor, because it is the
  constraint that actually binds: it batches dust into proofs that pay for
  themselves, and stops anyone spamming the worker with penny harvests.

### The score only moves while there is debt

Harvests cannot retire debt that is not there. **If Ada repays fully and does not
redraw, her score freezes and she never graduates.**

So "debt hits zero" and "climb the ladder" pull against each other, and the demo
has to pick. The resolution: **yield arriving with no outstanding debt accrues to
Ada as a withdrawable balance on Creditcoin**, and redrawing is a deliberate act
she takes at her new, higher limit.

That is one button in the frontend, it is how revolving credit actually works,
and it turns the awkward moment into the good one — *she finishes her first loan,
sees her limit go up, and chooses to use it.*

### Why it is measured in dollars repaid, not repayments made

This matters, because the obvious version is broken. **Do not add points per
harvest.** Harvests may be triggered by anyone, so "one point per repayment"
means someone calls harvest a thousand times with a cent each and walks up the
ladder for free. Counting dollars makes the score cost exactly what it claims to
represent.

Dividing by collateral rather than by the amount borrowed closes the same hole
from the other side: borrowing $1, repaying $1, and calling that a perfect record
would otherwise buy the top tier instantly.

### The rule that must not be broken

**The limit is checked when Ada borrows, and never again.**

If her collateral value moves and her existing debt is suddenly above her limit,
**nothing happens.** We do not call in the loan, we do not demand a top-up, we do
not seize anything. Enforcing a limit retroactively *is* a liquidation, and that
would drag back in the price feeds, the keepers, and the outbound-enforcement
problem that this entire design exists to avoid.

The limit gates new borrowing. That is all it ever does.

### Be honest about what this score is

Ada **cannot default** — that is the point of the product. So the score is not
measuring credit risk; there is no risk to measure. What it measures is
**demonstrated repayment volume**: real dollars, verified by proof, retiring real
debt.

That is worth saying plainly, because it is still genuinely valuable — it is a
portable, cryptographically-backed repayment record, which is exactly the input
the cross-chain credit-score idea needed and never had. But pitch it as a
*graduation ladder built on verified history*, not as risk assessment. A judge
from a credit company will ask what happens on default, and "nothing can default"
is a strong answer only if we got there first.

### Where this goes next (roadmap, not hackathon scope)

Ada starts at 0 even if she has repaid loans on Aave and Compound for years —
because we cannot see them. **But Creditcoin can.** The same precompile that
proves her harvests can prove her past repayments on Ethereum, letting her import
an earned starting score instead of beginning at zero.

That merges this build with the portable-credit-score idea, makes the proving
machinery do double duty, and is the strongest phase-2 story available. It is
also a whole second subsystem — keep it in the pitch and out of the demo.

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

One chain (Base Sepolia), one asset, one yield source. On screen:

1. Ada deposits into the Ethereum vault.
2. The proof lands on Creditcoin — show the actual verification transaction.
3. Ada's loan appears on Creditcoin. Score 0, limit 10%, small loan.
4. Two or three harvests get proven. **The debt visibly drops each time.**
5. **Her score crosses a tier and the limit jumps.** She draws more, on credit
   she earned during the demo.
6. Debt hits zero — and she chooses to redraw at her new limit.

Step 4 is the money shot — that's the bit no other chain can do. Step 5 is the
one the judges will remember, because it is the only moment where a *credit
score* visibly moves on a *credit chain*.

Frontend goes in the existing `frontend/` app: her debt falling, the score dial
rising, and the list of proven harvests that caused both.

### The honesty problem

Years of yield don't fit in a three-minute demo. `GRADUATION_TARGET` at 20% cuts
the ladder from 8.5 years to 3.4, which is honest tuning rather than faking — but
it is still not three minutes. So we also speed up the clock: our own yield
source with a silly-high rate, or hand-triggered harvests.

**Say this out loud in the demo.** "We've compressed the timeline; here's the
real rate." A judge who catches hidden time-compression stops believing anything
else you showed. A builder who flags it first looks careful.

---

## Decisions I still need to make

1. **What does Ada actually borrow?** **Decided: a mock USD token we deploy on
   Creditcoin ourselves, clearly labelled as a mock.** See "What already exists on
   Creditcoin" below for why — the obvious answer (lend an existing token) turns
   out not to be available.

   Not CTC. If Ada's debt is denominated in a volatile asset while her yield
   arrives as dollars on Ethereum, then working out how much CTC debt "$25 of
   yield" clears needs a CTC/USD price — **which drags back in the price oracle
   this whole design exists to avoid.** No liquidations was supposed to mean no
   price feed anywhere. A 1:1 USD-denominated token keeps that promise: dollars
   in, dollars off the debt, no conversion.

   Minting a real synthetic (Alchemix's alUSD route) stays on the roadmap. The
   peg problem is smaller than it first appears during a hackathon — with no pool
   listing the token there is no market price to defend — but it only earns its
   keep once the token needs to be tradeable, which is phase 2.
2. **Where does the yield come from?** Real Aave on a testnet is credible but
   fiddly and slow. Our own mock yield contract is fast and controllable but must
   be labelled as a mock. Pick one and be upfront. **This also decides our track
   — see below.**
3. **How much can she borrow?** **Decided: the credit-score ladder — 10% at
   score 0, rising to a hard 50% ceiling at score 85.** See "The credit score"
   above. Alchemix's flat ~50% is the ceiling we graduate *toward* rather than
   start at. Still open: do the tiers step (10/20/30/40/50) or slide
   continuously? Steps are easier to show on screen and easier to reason about;
   a slider is smoother but the demo has to explain it. **Recommend steps.**
4. **Which source chain?** **Decided: Base.** Harvest gas on mainnet forces a
   ~$4,000 minimum deposit, which contradicts the inclusion story; on Base the
   floor is ~$100. See "Sizing" above.
5. **Who triggers the harvest?** Anyone (permissionless, more decentralised) or
   just us (simpler)? For the demo, just us is fine.
6. **What if two people deposit?** Does each get their own vault, or one shared
   pool with shares? **Shared pool is a lot more accounting.** For the hackathon,
   one vault per user.

---

## What already exists on Creditcoin (checked, Aug 2026)

Worth knowing before writing contracts, because it settles decision 1 and
confirms decision 2.

| Looked for | Found |
|---|---|
| A lending protocol to borrow from | **None.** |
| DeFi on the chain generally | PenguinSwap (a DEX, live on mainnet). PenguinBase is a dApp hub, Spacecoin is DePIN. |
| Tracked DeFi TVL | DefiLlama does not list Creditcoin as a chain. Zero of ~8,000 tracked protocols deploy there. |
| A canonical stablecoin (USDC etc.) | **None.** Not in Circle's deployment list. |
| Anything lending-shaped in `@gluwa/usc-contracts` v0.2.0 | Nothing. The package is writability messaging plus decode libraries. Its only DeFi-adjacent file, `IPenguinSwapV3Pool.sol`, is used for TWAP price maths to quote relayer fees. |

Credefi appears in Creditcoin's partnership announcements as a lending platform,
but it is an off-chain EU debt-financing business — not a money market our
contract can call.

**None of this breaks the design, and one part of it validates the design.**

- We are not borrowing *from* a protocol. Re-read step 3 of the walkthrough: our
  own loan contract is the lender. There is nothing to integrate with because we
  are building the thing.
- The yield — the one part that genuinely needs a mature market — comes from
  **Ethereum**, not Creditcoin. Decision 2 already pointed that way, and this
  confirms it: Creditcoin-native yield would have had nowhere to go.
- The emptiness is a rubric asset. First lending primitive on the chain is a
  better story than the 380th Aave fork.

**What it does change:** there is no existing token worth denominating the loan
in, hence decision 1. And there are no depositors on day one, so **we pre-fund
the loan contract ourselves** — state that openly rather than implying a
liquidity side that does not exist.

---

## Which track to submit under

**Answer: DeFi.** The track description names the product twice — "Build
**lending**, trading, liquidity, or **yield** applications on Creditcoin." A
lending product whose repayment engine is yield is a literal match. The hashtags
(#Perpetuals #Derivatives #Bridges #Liquid staking) are examples, not a
whitelist; the prose is the definition.

Why not the others:

| Track | Verdict |
|---|---|
| **RWA** | Only if the collateral becomes a tokenized real-world asset. See below — this is a live option, not a no. |
| **DePIN** | No hardware, no sensors. Nothing to claim. |
| **Gaming** | That was the PvP idea, set aside. |
| **AI** | There is no AI here, and bolting one on to qualify is the mistake flagged twice in `ideas-analysis.md`: no judging criterion rewards AI, so it costs Execution Capability and buys nothing. The track's wording ("verified cross-chain data... without centralized oracle operators") is tempting because it describes the **precompile** so well — but that is the substrate we already use, not an AI product. |

### The one honest route to RWA

This is coupled to decision 2 above. Pick Aave or a mock yield source and we are
DeFi. Pick a **tokenized treasury** as the collateral — Ada deposits a T-bill
token and real-world treasury yield pays down her loan — and the *same contracts*
qualify as RWA, on a hackathon whose slogan is "real world."

The catch is practical: that needs a tokenized-treasury token that actually
exists on our testnet. On Sepolia it probably means mocking it, and a mocked RWA
is a weaker RWA entry than a real DeFi one. **Worth ten minutes checking what is
deployed before deciding.**

### Do not chase a thinner track

The instinct to dodge a crowded DeFi field is understandable, but placement
matters far less than fit — judges score the rubric, not the tag. A submission
filed under RWA while visibly being a lending protocol reads as gaming the
taxonomy. A strong DeFi entry beats a strained RWA one.

(Any claim in this repo that RWA or DePIN is "less crowded" is speculation, never
measured. Do not restructure the build around it.)

### To confirm from the hackathon rules

- Can we enter more than one track?
- Is the track locked at registration, or chosen at submission? If the latter,
  this decision can wait until the yield source is settled.

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
- A *real* pegged stablecoin (we deploy a labelled mock USD token instead —
  no peg to defend, no backing claimed; see decision 1)
- Importing credit history from other chains (the phase-2 story — see "The credit
  score")
- Any way for the score to go *down*, or any penalty mechanism (nothing can
  default, so there is nothing to penalise)
- Multiple source chains
- Multiple collateral types
- Shared pooled vaults
- Liquidations (impossible here by design — that's the point)

---

## Glossary

| Term | Plain meaning |
|---|---|
| **Collateral** | The money Ada locks up to be allowed to borrow. |
| **Credit score** | 0–100. How much verified repayment Ada has to her name. Decides her borrowing limit. |
| **LTV / limit** | Loan-to-value. What share of her collateral Ada may borrow — 10% to 50%, set by her score. |
| **`GRADUATION_TARGET`** | Dollars of repayment needed to reach a perfect score. Set to 20% of collateral. The one constant that decides whether the ladder is demoable. |
| **Scale-invariant** | Deposit size cancels out of every timeline. A big deposit gets a big loan *and* big yield, so it repays no faster. |
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
