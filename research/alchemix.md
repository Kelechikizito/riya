# Alchemix v3, read against riya

Notes from the five docs pages plus three they link to (Liquidations, Fees, How
the Peg Works — the five reference these mechanics without defining them).

Sources:
`/user/concepts/self-repaying-loans`, `/myt-and-yield`, `/alAssets`,
`/transmuter`, `/redemption-rate`, `/liquidations`, `/fees`,
`/how-peg-is-maintained` — all on `alchemix-v3-docs.vercel.app`.

Everything below is either **[doc]** — stated in the docs — or **[deduction]** —
mine, from reading the docs against `ideas.md` / `edge_case.md`.

---

## 0. The finding that reframes everything

**In Alchemix v3, yield is not the main repayment engine. It is roughly 2% of it.**

There are two engines retiring debt **[doc]**:

| Engine | Source | Alchemix's own numbers |
|---|---|---|
| **Vault yield** | MYT earns, debt falls, borrower pays nothing | 90% LTV at ~5% yield ⇒ **~5.5% of debt/year** |
| **Scheduled redemptions** | Transmuter matures, protocol force-repays from borrower collateral | Their worked example: **267% of total system debt/year** |

The redemption-rate page's example — 1000 alETH queued, 0.25-year transmutation
time, 1500 alETH total debt — gives a redemption rate of **2.67×/year**. Against
a yield engine running at ~5.5%/year, the transmuter is doing **~50× the work**.

Two conclusions pull in opposite directions and **both are true**:

1. **riya only has the slow engine.** Alchemix built the transmuter because
   organic yield against a 90% loan takes ~18 years. riya has no second engine
   and — see §2.1 — structurally cannot have one. riya's honest headline is
   *years*, not *months*.
2. **riya's engine is the only one that is actually self-repaying.** A redemption
   takes 1 unit of debt **and** 1 unit of collateral **[doc: "redemptions are
   applied to your share of the debt"; "reserves an equal value of MYT from
   borrower collateral"]**. The borrower's equity is unchanged (minus the 0.25%
   fee). It is *forced deleveraging*, not free repayment. **[deduction]** Only
   yield gives the borrower something for nothing.

So: **riya has 100% of the genuinely self-repaying engine and 0% of the forced
deleveraging engine.** That is a defensible, purer product — and a slower one.
Pitch both halves; a judge who knows Alchemix will test exactly this.

Pitch line that falls out of it:

> "In Alchemix, other people's arbitrage shrinks your position. In riya, nothing
> touches your debt except your own yield."

---

## 1. Architecture map

Alchemix v3 is four layers. riya is three of them plus a proof hop.

| Alchemix | What it is **[doc]** | riya's counterpart |
|---|---|---|
| **MYT** (mixUSD/mixETH) | ERC-4626 vault on Morpho Vaults V2. DAO allocates across strategies with risk tiers. Deposit USDC → get shares; share price rises with yield. | Source-chain vault + `AaveV4Adapter`. **Does not exist yet as a token.** See §3.1. |
| **Alchemist** | Holds MYT as collateral, mints alAssets to 90% LTV, 0% interest, position is an NFT. | Creditcoin loan ledger. |
| **alAsset** (alUSD/alETH) | Synthetic. *Inside the protocol* 1 alAsset always cancels 1 unit of debt regardless of market price. | Mock USD token on Creditcoin (decision 1, `ideas.md`). |
| **Transmuter** | Queue alAssets → wait a governance-set Transmutation Time → protocol earmarks borrower collateral → at maturity you get 1 MYT per alAsset, alAsset burned. | **None, and none possible.** §2.1. |

The layer separation is the reusable idea: **the Alchemist never knows about the
yield strategies.** It only knows about MYT. `AaveV4Adapter.sol` already has the
right seam — keep it absolute: the ASC and the loan ledger must only ever know
*"N proven dollars arrived"*, never *"Aave"*.

---

## 2. What riya correctly does NOT need

Each of these is machinery Alchemix carries that riya can drop — with the reason,
because "we simplified" only reads as competence when you can say what you
dropped and why it was load-bearing *there* and not *here*.

### 2.1 The transmuter, the peg, and the redemption rate — all one thing

All three exist to answer a single question: **how does an alAsset holder get
back to the underlying?** **[doc]** The peg is soft and maintained *only* by the
transmuter's 1:1 exchange; the redemption rate is just a derived statistic about
transmuter throughput.

riya cannot build this, and it is not a truncation:

- The transmuter's payoff is **receiving source-chain collateral**. That is the
  outbound leg. `CLAUDE.md`'s writability constraint kills it by construction.
- A CTC-denominated transmuter (hand out CTC from a treasury instead of MYT) is
  the obvious workaround and it is **wrong**: it needs a CTC/USD price, which
  drags back the oracle that decision 1 in `ideas.md` exists to avoid.
  **[deduction — considered and rejected, worth saying so in the submission.]**
- With no exit path there is no arbitrage, no discount, no peg to defend.
  `ideas.md` already spotted this ("with no pool listing the token there is no
  market price to defend"). The docs confirm the *whole* peg apparatus is
  downstream of tradeability.

**But this is also riya's weakest joint — see §4.1.**

### 2.2 Liquidations — and Alchemix tells you exactly why riya is safe

Alchemix liquidates on exactly two triggers **[doc]**:

| Trigger | Threshold | Does it apply to riya? |
|---|---|---|
| Position exceeds liquidation threshold | **95% LTV** | **No.** riya's ceiling is 50% and debt only ever decreases. Unreachable by construction. |
| Oracle shows MYT NAV < system debt (strategy loss/exploit/slippage) | any | **Yes.** This is the Aave-hack risk in `edge_case.md`. |

This is a much sharper way to state riya's risk than `edge_case.md` currently
does **[deduction]**:

> riya faces one of Alchemix's two liquidation triggers, and answers it by
> absorbing the loss rather than liquidating.

Note also **[doc]**: "price volatility alone cannot cause liquidation since debt
and collateral are like-kind assets (ETH backs alETH, USDC backs alUSD)." That
is the *same argument* `ideas.md` decision 1 makes for a USD-denominated loan
token over CTC. **Cite Alchemix as prior art for it** — "Proven Models" is a
scored criterion and this is a free point.

### 2.3 The oracle

Alchemix needs a NAV oracle purely to detect liquidation trigger 1. No
liquidations ⇒ no oracle ⇒ the "no price feed anywhere" promise survives intact.

---

## 3. What riya should take from Alchemix

Ranked by value per unit of build effort.

### 3.1 Make the source-chain vault an ERC-4626 — this collapses the mainnet minimum deposit

**The single highest-value item here.** It reverses decision 6 in `ideas.md`
("one vault per user").

`ideas.md` identifies the binding constraint honestly: the **harvest transaction
on Ethereum mainnet** is what costs money, forcing `MIN_HARVEST ≈ $100` and
therefore `MIN_DEPOSIT ≈ $2,000` — a number the doc rightly says "sits awkwardly
next to a pitch about financial inclusion."

With one vault per user, N users means **N harvest transactions and N proofs per
cycle**. With one shared ERC-4626 vault, N users means **one harvest transaction
and one proof**, regardless of N.

The $100 floor is then amortised across all depositors instead of borne by each:

| Depositors sharing the vault | Yield each must produce/yr | Deposit needed at 5% |
|---|---|---|
| 1 | $100 | $2,000 |
| 20 | $5 | $100 |
| 100 | $1 | **$20** |

**The mainnet minimum falls as ~1/N.** That converts a structural embarrassment
into a bootstrapping problem, which is a far better thing to have. It is also
exactly MYT's shape: one pooled vault, share price does the accounting **[doc]**.

`AaveV4Adapter.sol` is already 80% of the way there — `s_principal` and
`yieldAccrued() = totalAssets() - principal` is share accounting in all but name.
The vault above it wraps that as `totalAssets()`.

**The one hard part, and its answer.** A single `Harvested(assets)` event tells
Creditcoin a *total*; the ledger must split it across borrowers, and the shares
live on the other chain. Options:

- *(i)* Emit one event per position. N proofs again — defeats the point.
- *(ii)* **Mirror the share ledger on Creditcoin.** The Creditcoin ledger holds
  each user's vault shares, updated only by proven `Deposited`/`Withdrawn`
  events; harvest yield is distributed pro-rata against that mirror. **One proof
  per harvest at any N.** **[deduction]**

Option (ii) is the Alchemix-shaped answer and is the recommendation. It costs one
extra field in the source-chain events (shares minted/burned, which
`AaveV4Adapter` already returns) and a mapping on Creditcoin.

### 3.2 Add a performance fee — it is both the business model and the bad-debt backstop

Alchemix's fees **[doc]**:

| Fee | Rate |
|---|---|
| MYT performance fee | **15.00%** of yield |
| Ecosystem Vault fee (WETH, Ethereum) | 20.00% of blended yield |
| Borrower redemption fee | 0.25% of repaid debt |
| Transmuter early-withdrawal penalty | 2.50% (alETH) / 3.00% (alUSD) |
| Transmuter claim fee | 0.00% |

riya has **no revenue line anywhere in `ideas.md`**. A 15% cut of harvested yield
is about three lines in `AaveV4Adapter.harvest()` and it does two jobs:

1. **It is the proven model.** Alchemix, Yearn and Morpho all monetise this way.
   Directly scores "Proven Models" and "Product Vision".
2. **It funds the bad-debt backstop riya currently lacks.** `edge_case.md` says
   "we absorb the loss" if Aave is hacked — but riya has nothing to absorb it
   *with*. Alchemix has a DAO-funded fee vault for exactly this **[doc]**. The
   performance fee is where riya's would come from. **[deduction]**

Take the fee **on the source chain, inside `harvest()`, before the event fires**,
so the proven number is already net. Keeps "proof and value travel together"
(Rule 1) with no Creditcoin-side fee logic.

### 3.3 Ship the self-repay rate as a first-class number

riya cannot have a transmuter, but the *redemption rate concept* — "what share of
total debt gets retired in a year" — is computable for riya with no new contract
**[deduction]**:

```
self-repay rate = (collateral × yield rate) / (collateral × LTV) = yield rate / LTV
time to debt-free = LTV / yield rate
```

At 5% yield:

| Tier | LTV | Self-repay rate | Debt-free in |
|---|---|---|---|
| Score 0–19 | 10% | **50%/yr** | 2.0 yr |
| Score 20–39 | 20% | 25%/yr | 4.0 yr |
| Score 40–59 | 30% | 16.7%/yr | 6.0 yr |
| Score 60–84 | 40% | 12.5%/yr | 8.0 yr |
| Score 85+ | 50% | **10%/yr** | 10.0 yr |
| *(Alchemix)* | *90%* | *5.5%/yr* | *18.2 yr* |

Consistent with `ideas.md`'s own `LTV / rate` derivation — this just names it and
puts it on screen.

Why it earns its place:

- It is the honest way to communicate a slow timeline, in a metric Alchemix
  itself publishes to users.
- **It reframes the credit-score ladder.** The ladder currently reads as pure
  gatekeeping. With this number it becomes a genuine trade-off the user chooses:
  *a bigger limit means a slower self-repay.* Starting at 10% is not "we don't
  trust you", it is "your first loan clears itself in two years."
- The bottom row is the argument for riya's 50% ceiling against Alchemix's 90%.

### 3.4 Add manual repayment — but it must not count toward the score

Alchemix **[doc]**: "Send alAssets back at any time." riya has no manual repay
path at all.

Adding one (burn mock USD on Creditcoin, reduce debt) is cheap and fixes the
`ideas.md` "honesty problem" from a better direction than time-compression: the
demo can advance state in seconds using a **real feature** rather than a
fast-forwarded clock.

**The trap, and the rule that closes it. [deduction]** If manual repayment earned
credit score, the loop is free: borrow $100, repay $100, repeat. `ideas.md`
worries about this ("borrowing $1, repaying $1, and calling that a perfect
record") and answers it by dividing by collateral — which *caps* the exploit but
does not stop it. With $1,000 collateral, two instant borrow/repay round-trips of
$100 reaches the $170 graduation target at zero cost.

So:

> **The score counts only dollars that arrived from Ethereum with a proof.**
> Manual repayment reduces debt and frees limit, but earns no score.

That is a cleaner definition than the current one, and a better story: the score
measures **verified external cash flow**, which is precisely what makes it
portable and what makes the phase-2 "import your Ethereum repayment history"
roadmap coherent.

### 3.5 Make the Creditcoin position an NFT

Alchemix **[doc]**: "Your position is represented by an NFT available in your
wallet after the transaction confirms."

For riya this is nearly free and buys: a clean UI object, transferability (sell
your in-progress self-repaying loan), and composability. Note the angle
**[deduction]**: `ideas.md` establishes Creditcoin has essentially zero DeFi and
zero tracked TVL — so a riya position NFT would plausibly be **the first
composable DeFi primitive on the chain**. That is a User Base Expansion argument,
not just a feature.

**Tension to resolve, not ignore:** a transferable position carries the credit
score with it, which defeats "earned repayment history". Either keep the score
soulbound to the address while the position transfers, or state that the score
does not travel. Needs a decision; flagging rather than prescribing.

### 3.6 Keep the adapter seam, and say what it becomes

MYT's strategy risk tiers **[doc]**:

| Tier | Individual cap | Aggregate cap |
|---|---|---|
| Conservative | none | none |
| Moderate | 25% | 40% |
| Aggressive | 10% | 10% |

**Do not build this.** But `IAaveV4Spoke` + `AaveV4Adapter` is already the seam,
and "one adapter today; a weighted multi-strategy allocator with risk caps
tomorrow" is a roadmap sentence backed by code that already exists. Cheap.

### 3.7 Borrow the phrasing

- **"0% interest — balance declines, never compounding."** Better than anything
  currently in `ideas.md`.
- **"1 alAsset offsets exactly 1 unit of debt inside Alchemix"** — the
  face-value-vs-market-value distinction. riya needs the same sentence for its
  mock USD the moment that token can be traded.
- Alchemix's temporal-leverage note ("collateral continues earning yield while
  earmarked") validates `ideas.md`'s resolution that yield arriving with zero
  debt accrues as a withdrawable Creditcoin balance. Same instinct: never stop
  the yield.

---

## 4. What the Alchemix reading exposes as riya's weak points

### 4.1 "She now has spendable money on Creditcoin" is doing unearned work

This is the top open question.

alUSD trades near — but below — $1 **because it has a guaranteed 1:1 exit at
maturity** **[doc]**. That exit is the entire floor under its price.

riya's mock USD has **no exit path at all**, by §2.1. Step 3 of the README
("She now has spendable money on Creditcoin") therefore rests on Creditcoin
merchants or dApps accepting it — and `ideas.md`'s own survey found no lending
protocol, no canonical stablecoin, and zero DefiLlama-tracked protocols on the
chain.

Per `CLAUDE.md`'s "ask, don't assume": **what does Ada actually do with the
borrowed token on Creditcoin?** Candidate answers, none free:

- *(a)* Reframe honestly. It is a **credit balance**, not a redeemable claim; the
  demo shows debt mechanics and the score ladder, not spending. Cheapest, and
  arguably what the demo already shows.
- *(b)* Build a sink — a single Creditcoin contract that accepts it for
  *something* — so "spendable" is demonstrated rather than asserted.
- *(c)* Roadmap it: writability turns the token into a real redeemable claim and
  the transmuter becomes buildable. Good Product Vision, not demo scope.

`CLAUDE.md` warns against designs where the Creditcoin state is a *waypoint*
rather than the point. Right now the loan token is closer to a waypoint than the
spec admits. (a) is probably the right call for the hackathon, but it should be a
stated decision, not a silence.

### 4.2 riya's slowness is structural, not a tuning problem

`ideas.md`'s "honesty problem" section knows the demo is slow. What §0 adds is
that **riya cannot fix this in production either** — Alchemix's accelerator needs
a tradeable synth with an exit path, which needs writability.

Consequence: the low-LTV ladder is not conservatism, it is **the only speed lever
riya has**. Frame it that way. A judge asking "why 50% when Alchemix does 90%?"
gets: *because we deliberately have no liquidation engine and no redemption
engine, and 50% is what makes a loan self-clear in a decade instead of two.*

### 4.3 There is no backstop

Covered in §3.2. Alchemix has a DAO-funded fee vault; riya has nothing. The
performance fee is the fix.

---

## 5. Effect on the open decisions in `ideas.md`

| `ideas.md` | Alchemix reading says |
|---|---|
| **Decision 1** — mock USD, not CTC | **Confirmed.** Alchemix's like-kind-collateral argument is the same argument. Cite it. But see §4.1 — the token's *use* is still unanswered. |
| **Decision 3** — stepped 10→50% ladder | **Keep, and re-motivate.** §3.3 turns each tier into a self-repay speed. Steps still beat a slider. |
| **Decision 5** — who triggers harvest | Leave permissionless as `AaveV4Adapter.harvest()` already is. Alchemix's analogue is fully open. |
| **Decision 6** — one vault per user | **Reverse it.** §3.1: shared ERC-4626 + a mirrored share ledger on Creditcoin. Biggest single win available. |
| *(new)* Performance fee | **Add.** §3.2. |
| *(new)* Manual repayment | **Add, score-neutral.** §3.4. |
| *(new)* Position NFT | **Add, resolve score-transfer question.** §3.5. |
| *(new)* What is the token *for* | **Open — decide explicitly.** §4.1. |

---

## 6. Rubric check (`CLAUDE.md`)

| Criterion | Which items advance it |
|---|---|
| **User Base Expansion** | §3.1 (mainnet minimum falls ~1/N — the difference between an accredited-investor product and an accessible one), §3.5 (first composable primitive on Creditcoin) |
| **Technical Alignment** | Unchanged by all of this — the proof hop is still the load-bearing part. §3.1's *mirrored share ledger* makes the precompile do more work per proof, which is a plus. |
| **Product Vision** | §3.2 (revenue), §3.6 (allocator roadmap), §4.1(c) (writability → real transmuter) |
| **Execution Capability** | §2.1/§2.2/§2.3 — being able to name what was dropped and why is the readable evidence of a scoped plan |
| **Proven Models** | The whole document. riya = Alchemix's yield engine + the secured-credit-card ladder, on a substrate where the collateral and the loan sit on different chains. |

**What Alchemix has nothing like:** the credit score. Alchemix is a flat 90% for
everyone from block one. The graduation ladder is riya's own layer, and it is the
one that belongs on a credit chain.
