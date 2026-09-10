# What "over-delivering" means, in observable behaviour

> Worked against riya. Every example below is something already in this repo, or
> something this repo is currently failing to do.

## The definition

Over-delivering is not *more*. More features, more chains, more slides — a judge
reads that as unfocused, and the hackathon rubric explicitly rewards "a narrow
working vertical slice over a broad partially-working one."

Over-delivering is the **gap between what a judge expects from a hackathon
project and what they find**. The expected baseline is: a happy-path demo that
works once, a README, and a claim. Everything above that line is surplus.

The useful thing about that framing is that the gap is measured in *observable
behaviour* — what a stranger can verify in ten minutes without trusting a word
you said. If a claim can only be confirmed by believing you, it is not
over-delivery. It is marketing.

**The test for every item below:** could someone who has never met you check
this, alone, from a fresh clone?

---

## A. The claims are checkable

### 1. One command reproduces the headline claim

*Observable:* clone, run one command, see the claim confirmed.

riya: `forge test` runs 159 tests across 14 suites. 149 of them need no network,
no `.env`, no faucet, no deployed address.

*Anti-signal:* "it works, here's a video." A video is a claim about the past. A
test run is a claim anyone can re-make.

### 2. The test names carry the specification

*Observable:* run `grep -rhoE "function test[A-Za-z0-9_]+" test/` and read the
output as prose. You should learn what the system guarantees without opening a
single test body.

riya:

```
testFuzzADepositNeverRaisesTheScore
testFuzzNoImpostorCanCreateCollateral
testFuzzSettlingTwiceChangesNothing
testFuzzDebtNeverExceedsHalfOfCollateral
testFuzzOnlyTheLedgerCanMintOrBurn
testFuzzARevertedSourceTransactionNeverApplies
testFuzzPackedEncodingWouldProduceADifferentKey
```

That list *is* the threat model. A judge who reads only the test names has
already been told what the protocol promises and what it defends against.

*Anti-signal:* `testDeposit`, `testDeposit2`, `testBorrowWorks`. These name the
function under test, not the property. They tell a reader nothing they could not
have guessed from the file name.

### 3. Properties, not examples

*Observable:* the suite contains universals — "never", "always", "exactly",
"conserves" — exercised over generated input, not three hand-picked numbers.

riya: three fuzz suites, 256 runs per property.
`testFuzzSettlementConservesPendingYield` and
`testFuzzProRataSplitNeverOverPays` are conservation laws. An example test says
"this input gave the right answer." A property says "no input gives a wrong one."

*Anti-signal:* every test hardcodes `100e6` and passes.

### 4. The tests touch the real system, not only your mocks

*Observable:* at least one test fails if the *external* thing changes, not just
if your code changes.

riya: 10 fork tests execute against live Creditcoin Testnet — including
`testLiveRegistryAgreesWithTheHardcodedChainKeys`, which reads the real chain
registry through the Chain Info Precompile and asserts Sepolia is key 1 and
Ethereum Mainnet is key 3. `RiyaEscrowMainnetTest` runs the adapter against
genuine Aave V4 on a mainnet fork.

This is the difference between "my contract works against a mock I also wrote"
and "my contract works against the thing it will meet in production." Only the
second is evidence.

*Anti-signal:* a mock that returns exactly what the code under test expects,
with nothing checking that the mock resembles reality.

### 5. The rig fails loudly rather than skipping

*Observable:* break the environment on purpose — unset a required variable — and
watch what happens.

riya: the fork suite resolves through the `creditcoin_testnet` alias in
`foundry.toml`, so a missing `CREDITCOIN_RPC_URL` **fails**. It used to
`vm.skip`, which meant a run silently covered 149 of 159 tests and still printed
green.

A green run that quietly tested less than it claimed is worse than a red one.

*Anti-signal:* CI is green because the interesting suite skipped.

---

## B. The integration is deep, not decorative

### 6. The primitive is used where it is hard, not where it is easy

*Observable:* find the place where the platform's primitive returns, and read
what the code does *next*. Trusting the return value is integration. Knowing
what it does not cover is depth.

riya: `RiyaASC.submit` performs three checks the Block Prover Precompile does
**not** make, each closing a named attack:

| Check | Attack it closes |
|---|---|
| Replay key (chain + height + root + txIndex) | Replaying one real harvest until every borrower's debt hits zero |
| `receiptStatus == 1` | A reverted transaction still sits in a block and still proves cleanly |
| `log.address_` pinned per event | Anyone can deploy a contract emitting `TokensHarvested` with a value of one billion |

*Anti-signal:* calling the precompile, checking it returned true, and proceeding.

### 7. It would break on a different substrate

*Observable:* ask "could this ship on Base unchanged?" and check whether the
answer is grounded in the code.

riya: remove `0x0FD2` and there is no way for the loan to learn its collateral
earned anything. The product stops existing rather than getting slower. That is
the rubric's red-flag test, inverted into evidence.

*Anti-signal:* a project whose chain choice is a deployment target rather than a
dependency.

### 8. The off-chain half is engineered, not scripted

*Observable:* find the failure handling. Every cross-chain system has an
off-chain component; most hackathon versions are a `while(true)` loop.

riya: `offchain/src/worker.ts` distinguishes permanent failures from retriable
ones and dead-letters the permanent set, because retrying `RiyaASC__NoRelevantLog`
forever blocks every later event behind it. Reverts are decoded against both the
ASC and the ledger ABIs, since `submit` calls straight into `LoanLedger` and a
revert raised there surfaces as the ASC call failing.

And the sharpest instance: a test asserts the worker's replay key matches the key
`RiyaASC` derives from the same inputs, plus a second test that packed encoding
would produce a *different* key. Two independent implementations of one
derivation, pinned to each other.

*Anti-signal:* the off-chain worker is a gist in the README.

### 9. Deployment is reproducible and self-checking

*Observable:* read the deploy script for assertions, not just transactions.

riya: `RiyaUSD`, `RiyaASC` and `LoanLedger` have mutually circular constructor
pins. The script predicts each address with `vm.computeCreateAddress` and then
**asserts the prediction afterwards** — because a shifted nonce does not fail
loudly, it deploys a token that rejects every mint the real ledger attempts. The
destination script additionally validates its chain key against the live Chain
Info Precompile, since a wrong-but-nonzero key deploys cleanly and then reads the
wrong chain forever.

*Anti-signal:* addresses pasted into a config file by hand after the fact.

---

## C. It tells the truth about itself

### 10. The risk that could sink it is stated first, by you

*Observable:* the project has a Risks section, and the first item is a real
failure mode rather than a disclaimer about testnet.

riya: "If Aave is impaired, Riya absorbs it." Yield is measured as holdings minus
principal; if the reserve takes a loss the collateral shrinks while the
Creditcoin debt does not, and there is no liquidation path.

A risk a judge finds on their own discounts everything else on the page. A risk
you name first buys credit for everything else on the page.

*Anti-signal:* a Risks section that lists only "smart contracts are risky."

### 11. Named risks have named answers — or are labelled as unanswered

*Observable:* for each stated risk, either a designed response, or an explicit
"we have not solved this."

riya: the impairment risk now carries its answer — a shortfall is provable the
same way yield is, absorbed by the accrued fee, then spread across collateral,
with impaired collateral no longer backing new borrowing — and says plainly that
this **prices** a loss rather than refunding one, because refunding needs the
outbound leg. It is marked "designed, not built."

Naming a risk without a response reads as unexamined. Claiming a response you
have not built reads as dishonest. "Designed, not built" is the honest third
option and costs nothing.

### 12. It states what it is *not*

*Observable:* look for the sentence that gives up a flattering description.

riya: rUSD's NatSpec calls it "a dollar-denominated credit token, not a
stablecoin. There is no peg." It would have been free to say "stablecoin."

*Anti-signal:* every noun chosen for maximum impressiveness.

### 13. Blocked work is labelled blocked, and nothing on the critical path waits for it

*Observable:* check whether the roadmap distinguishes "we haven't done it" from
"we cannot do it yet," and whether the demo depends on anything in the second
category.

riya: Phase 3 is headed "Blocked on protocol capability" — writability is in
third-party audit and additional source chains do not exist. Nothing in Phases
0–2 touches them, and the demo does not either.

*Anti-signal:* a roadmap where everything is Phase 0 and nothing is sequenced.

---

## D. Craft nobody asked for

### 14. The history reads as a build

*Observable:* run `git log --oneline` and see whether a stranger can follow the
construction, then check out a commit at random and build it.

riya: atomic commits with conventional messages, each independently revertable,
each leaving the tree compiling.

*Anti-signal:* three commits, the last of which is "final fixes" touching 84
files.

### 15. Documentation exists at more than one altitude

*Observable:* count the distinct audiences served.

riya: a README pitch for someone who has never heard of it; eight `walkthrough/`
checkpoints for someone building it; NatSpec for someone auditing it. The NatSpec
explains **why**, not what — for instance, why `_dispatch` uses `continue` on an
impostor log but `revert` when nothing relevant is found (reverting on the
impostor would let anyone block a real proof by planting a fake log beside it).

*Anti-signal:* `/// @notice Deposits tokens` above `function deposit`.

### 16. It answers the question before it is asked

*Observable:* the obvious sceptical question has already been addressed in
writing, at the place where it occurs to you.

riya: why doesn't cash repayment raise the credit score? Because borrow-$100 /
repay-$100 on a loop would buy the top tier without the collateral ever doing any
work. That reasoning sits in a comment directly above the line that omits the
update.

---

## Where riya is *not* over-delivering right now

Applying the same standard inward, because a document like this is worthless if
it only flatters:

1. **User-visible typos on the landing page.** "increses with your usage"
   (`HowItWorks.tsx`), "readeability worker" (`Onboarding.tsx`), "writabliity"
   (`WhyCreditcoin.tsx`), "his phase is about" (`Roadmap.tsx`), "Additional
   source chains asides Ethereum Mainnet" (`Roadmap.tsx`). Typos on the one page
   every judge definitely reads undercut the care demonstrated everywhere else —
   and they cost minutes to fix.
2. **A dead CSS class.** `CreditLadder.tsx` uses `text-bold`, which is not a
   Tailwind utility and not a project token, so that label silently lost its
   styling.
3. **The fee is promised twice.** The Risks card says the accrued fee absorbs a
   shortfall first; `README.md` proposes minting that same fee as rUSD to a
   treasury. Both spend the same 15% margin. Two documents contradicting each
   other is exactly the thing a careful judge notices.
4. **`s_protocolFees` is uncollectable in v1.** Named honestly in the README,
   which is right — but it is currently a risk without an answer in the shipped
   surface.

---

## The ten-minute judge simulation

Run this against your own project before submission. Do it from a fresh clone,
with no `.env` you did not document.

- [ ] `git clone` → `forge test`. Does it go green without you intervening?
- [ ] `grep` the test names. Do they state the guarantees?
- [ ] Delete one required env var. Does the suite fail, or quietly skip?
- [ ] Open the file where the platform primitive is called. Is there anything
      after the success check?
- [ ] Ask "could this ship unchanged on another chain?" Is the answer in the code?
- [ ] Read the Risks section. Is the first item something that could actually sink you?
- [ ] For each risk: answer, or explicitly unanswered?
- [ ] `git log --oneline`. Does it read as a build?
- [ ] Read the landing page aloud. Any typos?
- [ ] Do any two documents contradict each other?

The last two are the cheapest points on the list and the most commonly dropped.
