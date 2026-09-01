# Checkpoint 7 · `RiyaUSD` — the borrowable dollar

> Part of the riya guided build. File to create: `src/RiyaUSD.sol`.
>
> The smallest contract in the system and the one most likely to be got subtly wrong.
> Roughly 30 lines of code and four decisions, one of which is a silent 1,000,000×
> bug.

---

## The job

`RiyaASC` (checkpoint 6) can now credit collateral and retire debt. Neither of those
hands the user anything spendable. `RiyaUSD` is the thing they actually walk away with.

It moves in exactly two places:

| Action | Token movement |
|---|---|
| Deposit proven | none — collateral is a number in the ledger |
| **Harvest proven** | **none — debt is decremented** |
| User borrows | `RiyaUSD` minted to them |
| User repays manually | `RiyaUSD` burned |

Note rows two and four are *not* the same event. Yield retires debt without burning
anything. That asymmetry is not an oversight — it is the entire economics of the
protocol, and section 2 is about why.

---

## Why there is a token at all

There is a real temptation to skip it. Debt is a `uint256`; a borrow could be nothing
but `s_debt[user] += amount` and a frontend that renders the number. Zero contracts,
zero mint authority, one less thing to audit.

Resist it, for one reason: **a loan you cannot spend is a scoreboard.** The submission's
claim is that Ethereum yield-holders get something natively useful on Creditcoin. A
balance that only riya's own frontend can read is not useful; an ERC-20 that any
Creditcoin contract, wallet, or DEX can accept is. This is the "destination state living
on Creditcoin is the point" test from `CLAUDE.md`, and a number in a private mapping
fails it.

The token is also the cheapest possible answer to *"so what does the user do next?"* —
the question that separates a demo from a product.

---

## The invariant that makes it honest

This is the part worth understanding before writing a line, because it is both the
protocol's best argument and the thing a sharp judge will probe.

Mint happens on borrow. Burn happens on manual repayment. **Yield-based settlement
burns nothing** — Alice's `s_debt` falls, but the `RiyaUSD` she already spent is out in
the world. So supply and debt do not track each other:

```
totalSupply(RiyaUSD)  =  Σ outstanding debt  +  Σ debt retired by proven yield
```

Follow the worked example from `research/how-value-and-proofs-move.md`:

| | escrow USDC | Alice's debt | RiyaUSD supply |
|---|---|---|---|
| Alice deposits $1,000 | $0 (all in Aave) | $0 | 0 |
| Alice borrows $100 | $0 | $100 | 100 |
| Harvest of $35 lands | **$35** | **$65** | 100 |
| Alice repays $65 in cash | $35 | $0 | **35** |

At every row, every `RiyaUSD` in circulation is backed by one of two things:

- **an outstanding loan**, over-collateralised by USDC locked in the escrow at ≥2× (the
  LTV ladder tops out at 50%), or
- **USDC that has already arrived in the escrow** as harvested yield.

The second column and the fourth converge as debt is retired. That is not a coincidence
and it is worth stating in the submission: the escrow's growing balance is the reserve
backing every dollar of debt riya ever forgave.

There is even a margin. The ledger takes a 15% fee, so only 85% of each gross harvest is
distributed into `s_yieldPerShare` — while 100% of it landed in the escrow. Reserve
outruns retired debt by the fee.

### The honest caveat

**`RiyaUSD` is not redeemable, and v1 cannot make it redeemable.** Handing a holder USDC
on Ethereum needs the outbound leg, and writability is off the table (`CLAUDE.md`, hard
constraint 1). The backing above is real and it is locked; it is also, in v1, a claim
nobody can exercise.

Say this plainly rather than letting a judge find it. The framing that survives scrutiny:

> `RiyaUSD` is a credit instrument issued against escrowed collateral, fully reserved and
> not yet redeemable. Redemption is the first thing writability unlocks.

The framing that does not survive scrutiny is calling it a stablecoin. A stablecoin
implies a peg and an arbitrage path that closes it, and there is neither. Name it a
dollar-denominated credit token in the README and the problem evaporates; call it a
stablecoin and every question after that one is hostile.

---

## The shape

```solidity
contract RiyaUSD is ERC20 {
    error RiyaUSD__NotLedger();
    error RiyaUSD__ZeroAddress();

    address public immutable I_LEDGER;

    modifier onlyLedger() {
        if (msg.sender != I_LEDGER) revert RiyaUSD__NotLedger();
        _;
    }

    constructor(address ledger) ERC20("Riya USD", "rUSD");

    function decimals() public pure override returns (uint8);
    function mint(address to, uint256 amount) external onlyLedger;
    function burn(address from, uint256 amount) external onlyLedger;
}
```

No owner. No pause. No cap. No mint role that can be granted. One immutable address, set
at construction, and nothing that can change it afterwards — the same posture as the two
Ethereum contracts, for the same reason: there is no admin key for a judge to find.

---

## Four decisions before writing it

### 1. `decimals()` must return 6 — this is the bug

OpenZeppelin's `ERC20` returns **18**. Every other number in riya is in USDC's **6**.

`HelperConfig` sizes `MIN_DEPOSIT` at `100e6`. The escrow forwards raw USDC amounts. The
adapter's `TokensHarvested` carries raw USDC amounts. `RiyaASC` reads `topics[2]` and
passes it through untouched. `LoanLedger` stores `s_collateral` and `s_debt` in those
same units. Then `borrow(100e6)` mints `100e6` base units of an 18-decimal token — which
every wallet on Creditcoin renders as **0.0000000001 rUSD**.

Nothing reverts. Nothing looks wrong on-chain. The demo just shows a user borrowing a
hundred dollars and receiving a rounding error.

Worse is the reverse trap. If the frontend "helpfully" scales up and mints `100e18`,
then `repay` burns `100e18` against a debt stored as `100e6`, and the arithmetic in
`LoanLedger` is off by a factor of a trillion in the user's favour.

```solidity
function decimals() public pure override returns (uint8) {
    return 6;
}
```

`pure`, not `view` — it reads nothing. Write it first, before the mint function, and put
a test on it in checkpoint 9. It is one line and it is the highest-value line in the file.

> **The rule:** one unit of account through the whole system, and it is USDC's. The two
> chains already agreed to share a unit rather than a token — do not break that agreement
> at the last contract.

If riya ever supports a second source asset with different decimals, this becomes a real
design problem rather than a one-liner. That is a roadmap footnote, not a v1 concern.

### 2. `burn(from, amount)` or `ERC20Burnable.burnFrom`?

`research/build-plan.md` step 5 writes `i_loanToken.burnFrom(msg.sender, paid)`.
`burnFrom` is OZ's, and it spends an **allowance** — so the user must `approve` the
ledger before they can repay.

| | ledger-only `burn(from, amount)` | `ERC20Burnable.burnFrom` |
|---|---|---|
| Transactions to repay | 1 | 2 (approve, then repay) |
| Standard behaviour | no — a bespoke function | yes |
| Who can burn whose tokens | the ledger, anyone's | anyone, with allowance |

**Take the ledger-only `burn`.** The trust argument is that it grants the ledger nothing
it does not already have: a contract with unbounded mint authority is not meaningfully
constrained by lacking burn authority. And it removes an `approve` from the demo, which
is a real cost — every extra confirmation is a place a live demo stalls.

Be precise about what it is, though. Mint dilutes; burn *confiscates*. The safety comes
entirely from `LoanLedger.repay` only ever burning from `msg.sender` against their own
debt, which means **that function is the security boundary, not this one.** Write the
constraint down in `RiyaUSD`'s NatSpec so the next reader knows where to look.

If you would rather keep the standard behaviour, inherit `ERC20Burnable`, drop the custom
`burn`, and add the `approve` step to the demo script. Defensible — just do not discover
the extra transaction on stage.

### 3. Transferable? Yes, and this one is settled

The position NFT (`build-plan.md` step 7) has a genuine open question about
transferability. `RiyaUSD` does not. Make it non-transferable and it is a scoreboard
again, and section 2 was about why that fails the submission's central claim.

Note what this means for the credit score: transferring `RiyaUSD` does not transfer debt.
Alice can send her borrowed dollars to Bob; her debt, her collateral, and her score stay
with her. That is correct — it is a loan, not a bearer obligation — and it is why the
ledger keys everything on the *borrower*, never on the token holder.

### 4. Where does the file go?

The tree is currently asymmetric. `RiyaEscrow` sits under
`src/source-chain/ethereum/`, but `RiyaASC` sits at `src/` root. `RiyaUSD` and
`LoanLedger` are both about to land, so pick now:

- **`src/` root for all three Creditcoin contracts** — least churn, and the Ethereum
  subdirectory keeps carrying the "this one is foreign" signal.
- **`src/destination-chain/creditcoin/`** — symmetric with the source-chain path, and it
  makes the two-chain architecture legible from the file tree alone, which is worth
  something to a judge skimming the repo.

The second is better and costs one `git mv` of `RiyaASC.sol` plus an import fix. Do it
now, before there are three files to move and a deploy script referencing them.

---

## The second lock

`research/how-value-and-proofs-move.md` describes two locks in series:

```
proof → ASC ──(only the ASC)──▶ LoanLedger ──(only the ledger)──▶ RiyaUSD.mint()
```

Checkpoint 8 builds the first. This checkpoint builds the second, and it is the simpler
half: one immutable, one modifier, no roles.

What it guarantees is worth stating exactly, because it is narrower than "the token is
safe": **`RiyaUSD` cannot come into existence except through a borrow that passed the LTV
check.** It says nothing about whether that check is correct — that is entirely
`LoanLedger`'s problem, and it is where checkpoint 8's attention belongs.

### The circular deploy, a third time

You have now met this pattern twice: adapter ↔ escrow (checkpoint 3) and ASC ↔ ledger
(checkpoint 6). This is the third pair.

`RiyaUSD` needs the ledger's address; `LoanLedger` needs the token's. Same resolution,
same script:

```solidity
uint256 nonce = vm.getNonce(deployer);
address predictedLedger = vm.computeCreateAddress(deployer, nonce + 1);

riyaUSD = new RiyaUSD(predictedLedger);          // trusts the prediction
ledger  = new LoanLedger(asc, address(riyaUSD)); // takes the real address

if (address(ledger) != predictedLedger) revert;  // prove it, do not assume it
```

But note the Creditcoin side has **three** contracts in one cycle, not two: the ASC needs
the ledger, the ledger needs the ASC *and* the token, and the token needs the ledger.
Only one of those needs predicting if you order it right — deploy the token against a
predicted ledger, then the ASC against the same predicted ledger, then the ledger last
with both real addresses. One prediction, three contracts, all immutable.

Work the nonce arithmetic out on paper before writing the script, and keep the
post-deploy assertion from `DeployRiyaSourceChain`. A shifted nonce here does not fail
loudly; it deploys a token that will reject every mint the real ledger ever attempts.

---

## What it deliberately is not

| Not | Because |
|---|---|
| Rebasing | Debt lives in the ledger. A token whose balance moves on its own would be a second copy of accounting — the exact bug class checkpoint 3 deleted. |
| Interest-bearing | Same reason. Interest, if it ever exists, is a ledger number. |
| Pegged | There is no arbitrage path to close a peg, so claiming one is a claim you cannot back. |
| Permit-enabled | `ERC20Permit` costs a constructor argument and a domain separator to save an `approve` that decision 2 already removed. |
| Capped | The cap is the LTV ladder, enforced in the ledger. A supply cap here would be a second, weaker copy of it. |

Every row is the same instinct as the Ethereum contracts: keep the mechanism dumb, keep
the decision in one place.

---

## Tests (checkpoint 9)

Constructor:

- zero ledger → `RiyaUSD__ZeroAddress`
- `I_LEDGER()` returns the address passed
- **`decimals()` returns 6** — the cheapest test in the repo and the one that catches the
  worst bug
- `name()` / `symbol()` are what the frontend expects

Authority:

- `mint` from a non-ledger address → `RiyaUSD__NotLedger`
- `burn` from a non-ledger address → `RiyaUSD__NotLedger`
- `mint` from the ledger → balance and `totalSupply` both move by exactly `amount`
- `burn` from the ledger → same, downward
- burning more than the holder's balance → reverts with OZ's
  `ERC20InsufficientBalance`, not silently clamped

Behaviour:

- a plain `transfer` between two users succeeds (the non-negotiable from decision 3)
- there is no function anywhere on the contract that changes `I_LEDGER` — assert by
  reading the ABI, not by trying to call one

Integration (once checkpoint 8 lands):

- `borrow` mints exactly the borrowed amount, in 6-decimal units
- `repay` burns exactly the repaid amount and leaves `s_repaidByYield` untouched
- after a proven harvest retires debt, `totalSupply` is **unchanged** — this is the test
  that pins the invariant from section 2, and it is the one that will surprise someone
  reading the suite cold. Comment it.

---

**Next:** Checkpoint 8 — `LoanLedger`, where every decision in riya actually lives: the
collateral mirror, the pro-rata accumulator, the credit score, and the LTV ladder that
`RiyaUSD` is only as safe as.
