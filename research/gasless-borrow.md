# Gasless borrow on Creditcoin — research notes

> **Status: recommended, not adopted.** Deferred to a later checkpoint by
> decision on 2026-08-27. Nothing in the current build depends on it. This file
> exists so the reasoning does not have to be reconstructed later.

---

## Where the idea came from

Four projects won the DeFi & Payments track at a Sui hackathon (Quay, Talise,
Brisk, Splash). None of their payment mechanics transfer to riya — there is no
merchant, no point of sale, no payment moment here.

What transfers is **why** they won: every one of them removed a step from
something the user was already doing. None asked the user to learn a new
financial primitive. They won on friction, not novelty.

Counting riya's steps for a first-time user:

1. Have ETH on Ethereum (gas)
2. Have USDC on Ethereum
3. Approve, deposit
4. Wait for attestation
5. **Acquire CTC** — a token they have never held
6. Switch to a chain their wallet is not configured for
7. Borrow

Seven steps, two chains, two gas tokens. Step 5 is the worst of them: the user
must go buy CTC on an exchange before they can touch collateral **they already
deposited**. The Sui winners are at one or two steps.

---

## The verdict

**It works, and it is cheaper than it first looks.** Four reasons, each verified
against the repo rather than assumed.

### 1. The surface is two functions

Per `how-value-and-proofs-move.md`, the readability worker already pays CTC for
every deposit-crediting and harvest-crediting transaction. Those are *already*
gasless from the user's side.

The only Creditcoin transactions a user ever signs are:

- `borrow()`
- `repay()`

This is not sponsoring an app. It is sponsoring two calls.

### 2. The dependency is already installed

OpenZeppelin 5.7.0, already in `lib/`, ships both halves:

```
lib/openzeppelin-contracts/contracts/metatx/ERC2771Forwarder.sol
lib/openzeppelin-contracts/contracts/metatx/ERC2771Context.sol
```

Nothing to add, no new audit surface beyond the pattern itself.

### 3. `LoanLedger` does not exist yet

`src/` currently holds five files, none of them the ledger. The cost today is
one inheritance line plus using `_msgSender()` in place of `msg.sender` while
writing it.

Retrofitting after deployment means a redeploy. **This is the cheapest moment it
will ever be** — which is the one argument for not deferring it too far.

### 4. The relayer already exists

The readability worker is an off-chain Node process with a funded CTC key that
writes to Creditcoin. It becomes the forwarder's relayer. One process, one
funded key, no new infrastructure.

### And it needs no writability

Every part of this is Creditcoin-side. It does not touch the constraint that
shapes the rest of the project.

---

## The trap: two callers, two authentication models

`LoanLedger` is called along two paths that authenticate differently:

| Caller | Path | Who must be trusted |
|---|---|---|
| ASC → `onDeposit` / `onHarvest` | proof-verified | the ASC contract |
| User → `borrow` / `repay` | signature-verified | the forwarder |

Inheriting `ERC2771Context` naively rewrites `_msgSender()` for **both**. A
relayer could then spoof the ASC path — which is the path carrying proven
cross-chain value, so this is the whole security model, not a corner case.

The fix is routine: trust the forwarder only on the user functions, and keep the
ASC path on a plain `msg.sender == i_asc` check. But it has to be deliberate,
and it is far easier to build in than to retrofit.

> Write the ledger with both paths distinct from the first line, even if the
> forwarder is not wired up until later.

---

## The honest cost problem

The relayer needs CTC to spend.

The 15% protocol fee accrues on Creditcoin **as a number in a ledger**, not as
spendable CTC. So the treasury cannot pay its own gas bill. The relayer is
funded out of pocket.

- **Demo:** free. Testnet gas costs nothing, so this does not bind at submission.
- **Production:** a real, ongoing cost.

The defensible framing is that sponsored gas is a customer-acquisition cost,
capped per user — which is exactly how every payments app on that Sui list
operates. That is a fine answer. It is only a hole if a judge finds it before
you say it.

---

## Scoring it honestly against the rubric

| Criterion | Effect |
|---|---|
| **User Base Expansion** | Strong. Removes the single worst drop-off in the funnel. |
| **Proven Models** | Strong. Account abstraction / gas sponsorship is a recognised pattern, not an invention. |
| **Product Vision** | Moderate. Supports the "never leaving Creditcoin is a feature" story. |
| **Execution Capability** | Moderate. Small, well-understood, and the dependency is installed. |
| **Technical Alignment** | **None.** A relayer ships on any EVM chain unchanged. |

That last row is the one to keep in view. This is onboarding built *around* the
Creditcoin core, not part of it. It must never be presented as the technical
story — the ASC and the Block Prover Precompile are. If time is short, this is
cuttable; the proof pipeline is not.

---

## What to do, and when

| When | Action |
|---|---|
| Writing `LoanLedger` | Keep the ASC path and the user path authenticated separately, regardless of whether the forwarder is wired yet. Costs nothing now. |
| Later checkpoint | Deploy `ERC2771Forwarder`, inherit `ERC2771Context` on the user functions only, point the worker at it as relayer. |
| Submission write-up | State the sponsorship cost and its cap before anyone asks. |

---

## Open questions

- Per-user sponsorship cap, and what happens when a user hits it — does `borrow`
  fall back to self-paid, or refuse?
- Does the worker relay borrows from the same key it uses to submit proofs?
  Simpler, but one compromised key then does both jobs.
- Is `repay()` worth sponsoring at all? A user repaying has already borrowed, so
  the acquisition argument does not apply to them.

---

## Related

- `how-value-and-proofs-move.md` — who pays gas on which chain, and why the
  keeper and the worker are different jobs
- `build-plan.md` — where `LoanLedger` sits in the build order
- `CLAUDE.md` — the five judging criteria this is scored against
