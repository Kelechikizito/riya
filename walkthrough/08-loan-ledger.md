# Checkpoint 8 · `LoanLedger` — where every decision lives

> Part of the riya guided build.
>
> **File to create:** `src/destination-chain/LoanLedger.sol` (the stub is already there).
> The design comes from `research/build-plan.md` section 3; this checkpoint expands it,
> corrects the parts that have gone out of date, and marks the traps.

---

## 1. Two callers, two authentication models

Write this in before anything else. It costs nothing today and it cannot be added later
without redeploying the contract that holds everyone's collateral.

`LoanLedger` is reached along two paths that have nothing in common:

| Caller | Functions | Authenticated by | Trusts |
|---|---|---|---|
| `RiyaASC` | `onDeposit`, `onHarvest` | a **proof** already verified against the precompile | one address, fixed at deploy |
| A user | `borrow`, `repay` | an **ECDSA signature** over an intent | the user's key — or later, a forwarder |

The first path carries every dollar of proven cross-chain value in the system. The second
path decides how much of it someone may borrow. They are the only two ways into the
contract, and they should never share an authentication mechanism.

### Why this comes up now, before any forwarder exists

`research/gasless-borrow.md` recommends sponsored-gas borrowing — the user signs a
`borrow()` intent and the readability worker pays the CTC. That is **deferred to
checkpoint 10** and nothing here builds it.

But the deferred version is implemented by inheriting `ERC2771Context`, and
`ERC2771Context` overrides `_msgSender()` for **the entire contract**:

```solidity
function _msgSender() internal view virtual override returns (address) {
    if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
        return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
    }
    return super._msgSender();
}
```

There is no per-function granularity in it. Inherit it, write `_msgSender()` everywhere
out of habit, and the ASC path's identity check is now resolved through an external
contract instead of a plain address comparison.

**So the seam has to exist in the contract from the start**, even though nothing sits on
the other side of it yet. Retrofitting means redeploying the ledger, which means
migrating collateral. This is the cheapest moment it will ever be.

### Be accurate about the risk

`research/gasless-borrow.md` says a relayer *"could then spoof the ASC path."* Checked
against the installed code, **that overstates it**, and the overstatement is worth
correcting rather than repeating:

OpenZeppelin 5.7's `ERC2771Forwarder` validates with `ECDSA.tryRecoverCalldata` and
nothing else — no ERC-1271, no contract-signature path. To forward a call claiming
`from = i_asc`, an attacker needs a valid ECDSA signature from the ASC's address. `RiyaASC`
is a contract and has no private key. It cannot sign, so the direct spoof does not work
against the stock forwarder.

The argument for separating the paths is still strong; it is just a different argument:

1. **Trust surface, for zero benefit.** With `_msgSender()` on the ASC path, that path's
   security stops being "one address comparison" and becomes "the forwarder contract is
   correct, its EIP-712 domain is right, its nonce handling is sound, and the address we
   deployed is the one we meant." The ASC will never need a meta-transaction — it is a
   contract calling a contract. Paying that surface for a feature you cannot use is a bad
   trade at any price.

2. **The assumption is one config change from false.** The safety above rests entirely on
   the forwarder being ECDSA-only. `trustedForwarder()` is `virtual`, and a forwarder that
   supports ERC-1271 contract signatures is a normal thing to want later. The day riya
   swaps in one, a contract address becomes impersonable and the ASC path becomes
   genuinely exploitable — silently, with no code change to the ledger.

3. **The maintenance trap, which is the realest one.** In a contract inheriting
   `ERC2771Context`, a bare `msg.sender` *looks like a bug*. Linters flag it. Reviewers
   flag it. "Use `_msgSender()` for consistency" is the most natural review comment in the
   world, and applying it introduces the vulnerability. This is a human failure mode, not
   a cryptographic one, and it is the one most likely to actually happen.

Point 3 is why the fix is not just code — it is a comment loud enough to survive a
well-meaning cleanup.

### The fix

Routine, and about four lines:

```solidity
/// @dev DELIBERATELY `msg.sender`, NOT `_msgSender()`.
///      This path is reached only by `RiyaASC` calling directly, never through a
///      forwarder, and it carries every proof-verified dollar in the system. Resolving it
///      through ERC-2771 would make its security depend on the forwarder's signature
///      handling for a meta-transaction capability the ASC can never use.
///      If a linter or a reviewer asks you to "fix" this for consistency, the answer is
///      no. See walkthrough/08-loan-ledger.md.
modifier onlyASC() {
    if (msg.sender != I_ASC) revert LoanLedger__NotASC();
    _;
}
```

and on the other side:

```solidity
function borrow(uint256 amount) external {
    address user = _msgSender();   // forwarder-aware from checkpoint 10 onward
    ...
}

function repay(uint256 amount) external {
    address user = _msgSender();
    ...
}
```

Until checkpoint 10, `LoanLedger` does **not** inherit `ERC2771Context`, so `_msgSender()`
resolves through plain `Context` and returns `msg.sender`. Behaviour today is identical.
What you have bought is that checkpoint 10 becomes one inheritance line and a constructor
argument, touching neither `onDeposit` nor `onHarvest`.

> **The rule:** `msg.sender` on the proof path. `_msgSender()` on the user path. Never
> the reverse, and never both the same.

### Two smaller traps that come with the pattern

- **Calldata length.** OZ's own warning: a forwarded call arrives with 20 extra bytes
  appended. Do not write anything in `LoanLedger` that branches on `msg.data.length`.
  Nothing currently planned does — keep it that way.
- **`_msgSender()` is not free of context.** It reads calldata. Cache it in a local at
  the top of each user function rather than calling it repeatedly; it also makes the two
  paths visually distinct when reading the file.

### Tests for this section (checkpoint 9)

- `onDeposit` / `onHarvest` from any address other than the ASC → `LoanLedger__NotASC`
- `onDeposit` called with 20 bytes of address appended to the calldata, from a non-ASC
  address → still reverts. This is the test that pins the whole section; write it now and
  it keeps passing through checkpoint 10.
- `borrow` / `repay` attribute the position to `msg.sender` while no forwarder exists
- after checkpoint 10 only: a forwarded `borrow` credits the *signer*, not the relayer —
  and a forwarded `onDeposit` still reverts

---

## 2. State

The design comes from `research/build-plan.md` section 3. Three changes before you copy it
across.

**Immutable naming.** `build-plan.md` writes `i_asc` and `i_loanToken`. The repo settled on
uppercase for immutables: `RiyaASC` has `I_CHAIN_KEY`, `I_ESCROW_CONTRACT`, `I_LEDGER`, and
`RiyaUSD` has `I_LEDGER`. Use `I_ASC` and `I_RIYA_USD`.

**The token type.** `build-plan.md` says `IMockUSD`, written before `RiyaUSD` existed. It is
`RiyaUSD` now, and it lives at `src/destination-chain/RiyaUSD.sol`.

**No `IYieldAdapter` here.** The ledger never touches Ethereum. Every number it holds
arrived through a proof.

```solidity
uint256 private constant PRECISION = 1e18;
uint256 private constant GRADUATION_TARGET_BPS = 2_000;  // 20% of collateral
uint256 private constant FEE_BPS = 1_500;                // 15%, matching Alchemix's MYT fee
uint256 private constant BPS_DENOMINATOR = 10_000;

address public immutable I_ASC;
RiyaUSD public immutable I_RIYA_USD;

// collateral, credited from proven source-chain deposits
mapping(address => uint256) public s_collateral;
uint256 public s_totalCollateral;

// per-user position
mapping(address => uint256) public s_debt;
mapping(address => uint256) public s_repaidByYield;  // the score's basis
mapping(address => uint256) public s_credit;         // yield that had no debt to retire

// protocol
uint256 public s_protocolFees;                       // a claim on the Ethereum reserve

// pro-rata accumulator
uint256 public s_yieldPerShare;
mapping(address => uint256) public s_marker;
```

### Two things about the units

**Collateral is 1:1 with the dollars escrowed.** There is no share price anywhere in riya,
so there is nothing to float and nothing to manipulate. A proven deposit of 1000 USDC
becomes exactly 1000 units of collateral. This is why checkpoint 7 insisted on 6 decimals:
collateral, debt, and `RiyaUSD` are all the same unit, and the whole system holds together
because nothing ever converts.

**`PRECISION` is 1e18 and that is correct**, even though every amount is 6 decimals. It is
not a unit, it is a scaling factor for a ratio. `s_yieldPerShare` holds "yield per unit of
collateral", which is a fraction far below 1, and multiplying by 1e18 before dividing is
what stops it truncating to zero. The 1e18 cancels out again in `_settle`.

Work an example. A harvest of 85 USDC net across 1,000,000 USDC of collateral:

```
s_yieldPerShare += (85e6 * 1e18) / 1_000_000e6  =  85e12
```

Without `PRECISION`, that division is `85 / 1_000_000 = 0` and every harvest below the total
collateral silently distributes nothing.

---

## 3. The mirror updates

Two functions, both `onlyASC`, both driven only by proven events.

```solidity
function onDeposit(address user, uint256 assets) external onlyASC {
    _settle(user);
    s_collateral[user] += assets;
    s_totalCollateral  += assets;
}

function onHarvest(uint256 gross) external onlyASC {
    if (s_totalCollateral == 0) revert LoanLedger__NoCollateral();
    uint256 fee = (gross * FEE_BPS) / BPS_DENOMINATOR;
    s_protocolFees += fee;
    s_yieldPerShare += ((gross - fee) * PRECISION) / s_totalCollateral;
}
```

### `_settle` before the collateral changes, always

The `_settle(user)` on the first line of `onDeposit` is not bookkeeping tidiness. Remove it
and a depositor collects a share of every harvest that happened before they arrived.

Section 4 explains the mechanism. The rule to carry into every function you write here:
**call `_settle(user)` before touching `s_collateral[user]` or `s_debt[user]`, in every
function, without exception.** That is `onDeposit`, `borrow`, and `repay`. `onHarvest` is
the one that does not, because it changes no single user's position.

### The fee split

15% of gross goes to `s_protocolFees` and 85% is distributed. Note what that means for the
invariant in checkpoint 7: 100% of the harvest reached the escrow on Ethereum, but only 85%
of it retires debt. The reserve grows faster than the debt it forgives, and the gap is the
fee.

`s_protocolFees` is a number, not money. It is a claim on USDC sitting in the escrow on
Ethereum, and it becomes real only when withdrawals exist, which needs writability. Say that
plainly in the NatSpec rather than letting someone assume the protocol can spend it.

### The zero-collateral revert is a trap for your worker

`onHarvest` reverts with `LoanLedger__NoCollateral` when nothing is deposited yet. That is
correct as arithmetic, since dividing by zero collateral is meaningless.

The problem is what it does to `offchain/src/worker.ts`. A harvest proof that lands before
any deposit proof will revert, and `LoanLedger__NoCollateral` is not in the worker's
`PERMANENT_ERRORS` set. The worker treats it as retriable, and because the ordered queue
stops on a retriable failure, that one event blocks every later event forever.

In normal operation this cannot happen: the keeper only harvests once yield has accrued,
which requires a deposit, and the worker submits in source-chain order. It becomes reachable
if the first deposit proof is ever dead-lettered while the harvest behind it is not.

Two ways out, and you should pick one now rather than discover it during the demo:

- Add `LoanLedger__NoCollateral` to the worker's `PERMANENT_ERRORS` set. One line, and it
  matches the truth: a harvest with no collateral behind it will never become submittable.
- Or make `onHarvest` return early instead of reverting when `s_totalCollateral == 0`,
  treating the yield as unclaimed.

The first is better. A silent early return loses the yield with no record that it happened.

### Rounding

`((gross - fee) * PRECISION) / s_totalCollateral` truncates. The remainder stays in the
contract as yield nobody can claim. With `PRECISION` at 1e18 the loss is far below one
millionth of a cent per harvest, so it does not need handling, but do not write a test that
asserts the distributed total equals `gross - fee` exactly. It will not.

---

## 4. The accumulator

This is the part worth understanding before you write it, because it is the only non-obvious
algorithm in riya and the reason the demo works at all.

### The problem it solves

One proven harvest has to reduce the debt of every borrower, in proportion to their
collateral. The obvious implementation loops over depositors and updates each one. That is
O(n) gas in a single transaction, so the protocol stops working once it has enough users,
and it stops working at exactly the moment success arrives.

The MasterChef accumulator makes it O(1). Nobody's debt is written when the harvest lands.
Instead, one global number moves, and each user's share is computed later, the next time
they touch the contract.

### How it works

`s_yieldPerShare` is a running total of yield distributed per unit of collateral, ever.
It only goes up.

`s_marker[user]` records the value of `s_yieldPerShare` at the moment that user's position
was last settled.

The difference between the two is the yield per unit of collateral that has arrived since
the user last looked. Multiply by their collateral and you have their share:

```
pending = collateral × (s_yieldPerShare − s_marker[user]) ÷ PRECISION
```

That is the whole idea. `onHarvest` writes one storage slot regardless of how many users
exist, and `_settle` does the per-user arithmetic on demand.

### Worked example

Alice has 1,000 collateral, Bob has 3,000. Total is 4,000.

| Step | `s_yieldPerShare` | Alice's marker | Bob's marker |
|---|---|---|---|
| Both deposit | 0 | 0 | 0 |
| Harvest, 400 net distributed | `400e18/4000` = `1e17` | 0 | 0 |
| Alice borrows, so `_settle(alice)` runs | `1e17` | `1e17` | 0 |

At Alice's settlement, `pending = 1000 × (1e17 − 0) / 1e18 = 100`. She holds a quarter of
the collateral and gets a quarter of the 400. Bob's marker is untouched, so his 300 is still
waiting for him. Nothing looped over anyone.

---

## 5. `_settle`

```solidity
function _settle(address user) internal {
    uint256 collateral = s_collateral[user];
    uint256 acc = s_yieldPerShare;

    if (collateral != 0) {
        uint256 pending = (collateral * (acc - s_marker[user])) / PRECISION;
        if (pending != 0) {
            uint256 debt = s_debt[user];
            uint256 applied = pending < debt ? pending : debt;

            s_debt[user] = debt - applied;
            s_repaidByYield[user] += applied;     // the score counts proven dollars only
            s_credit[user] += pending - applied;  // surplus, when there is no debt left

            emit DebtRetired(user, applied, pending - applied);
        }
    }

    s_marker[user] = acc;
}
```

Four things in nine lines, and three of them are easy to get wrong.

### The first depositor looks like a bug and is not

A new user has `s_marker[user] == 0`. If `s_yieldPerShare` is already large when they first
deposit, the subtraction `acc - s_marker[user]` gives the entire history of the protocol,
and they appear to be owed a share of every harvest since launch.

They are not, because of the `if (collateral != 0)` guard. On their very first `onDeposit`,
`_settle` runs *before* the collateral is added, so `collateral` is still 0, the whole block
is skipped, and the last line sets their marker to the current `acc`. They start from now.

This is why the `_settle` call has to come first in `onDeposit` and why the guard cannot be
removed as a gas saving. Write a test for it, because reading the code alone makes it look
like free money.

### The marker moves even when nothing else does

`s_marker[user] = acc` sits outside the `if`. It has to. A user with zero collateral still
needs their marker brought up to date, or the moment they deposit they inherit a stale
marker and claim history they missed.

### Surplus becomes credit, not lost yield

If a user's pending yield exceeds their debt, the excess goes to `s_credit[user]`. This
implements `research/ideas.md`'s rule that yield arriving with no outstanding debt accrues
as a balance rather than evaporating.

Be honest in the NatSpec about what `s_credit` is in v1: a number with nothing to spend it
on. Paying it out means sending USDC on Ethereum, which needs writability. Two things it
could plausibly become, both of which belong in the roadmap rather than here:

- an offset against future borrows, which is pure Creditcoin state and buildable today
- a withdrawable balance once writability exists

Pick one later. Do not let it stay undefined in the submission, because a judge will ask.

### `_settle` is idempotent

Calling it twice in a row is safe. The second call finds `acc - s_marker[user] == 0`, so
`pending` is 0 and nothing happens. That matters because `borrow` and `repay` both call it
and you will sometimes call it defensively.

---

## 6. The score and the LTV ladder

```solidity
function score(address user) public view returns (uint256) {
    uint256 target = (s_collateral[user] * GRADUATION_TARGET_BPS) / BPS_DENOMINATOR;
    if (target == 0) return 0;
    uint256 s = (s_repaidByYield[user] * 100) / target;
    return s > 100 ? 100 : s;
}

function maxLtvBps(address user) public view returns (uint256) {
    uint256 s = score(user);
    if (s < 20) return 1_000;
    if (s < 40) return 2_000;
    if (s < 60) return 3_000;
    if (s < 85) return 4_000;
    return 5_000;
}
```

| Score | Max LTV |
|---|---|
| 0 to 19 | 10% |
| 20 to 39 | 20% |
| 40 to 59 | 30% |
| 60 to 84 | 40% |
| 85+ | 50% |

The score measures one thing: how much of your debt has been retired by yield, against a
target of 20% of your collateral. Retire that much through yield and you reach 100.

### Why manual repayment must not move the score

`repay` deliberately does not touch `s_repaidByYield`. If it did, anyone could borrow $100,
repay $100 in cash, and repeat until they reached the top tier without ever letting yield
work.

The behaviour being rewarded is forgoing yield, not moving money around. That is the
Alchemix idea adapted to riya, and it is the sentence to use if a judge asks what the score
actually measures.

Keep the comment in the code. `research/build-plan.md` says "one comment does the security
work here", and it is right.

### A quirk to decide on, not to discover

The score divides by *current* collateral. So depositing more lowers your score.

Alice has 1,000 collateral and 200 retired by yield, giving a score of 100 and a 50% LTV
tier. Her limit is 500. She deposits another 1,000, and her target doubles to 400, so her
score halves to 50 and she drops to the 30% tier. Her limit is now 600.

Her borrowing power went up, which is the outcome that matters. Her score visibly fell,
which the frontend will have to explain. Three options:

- Leave it. The score is "share of your collateral repaid by yield", and by that definition
  the drop is correct.
- Base the target on collateral at the time of first borrow, which needs another storage
  slot.
- Make the score absolute rather than relative, which makes it easy to farm with a large
  deposit.

The first is right for v1. Just make sure the frontend says "score is relative to your
collateral" somewhere, or your demo will show a deposit making a user look worse.

### The self-repay view

```solidity
/// @return bps Share of current debt retired per year at `yieldRateBps`.
function selfRepayRateBps(address user, uint256 yieldRateBps)
    external view returns (uint256 bps)
{
    uint256 debt = s_debt[user];
    if (debt == 0) return 0;
    return (s_collateral[user] * yieldRateBps) / debt;
}
```

No oracle. The frontend passes the observed Aave APY, and computes
`yearsToZero = 10_000 / selfRepayRateBps`.

Put that next to the score dial. It is what turns the LTV ladder into a speed trade-off the
user can reason about rather than a gate they are stuck behind.

---

## 7. `borrow` and `repay`

Both are the user path, so both resolve identity with `_msgSender()`, per section 1.

```solidity
function borrow(uint256 amount) external {
    address user = _msgSender();
    _settle(user);

    uint256 limit = (s_collateral[user] * maxLtvBps(user)) / BPS_DENOMINATOR;
    if (s_debt[user] + amount > limit) revert LoanLedger__ExceedsLimit();

    s_debt[user] += amount;
    I_RIYA_USD.mint(user, amount);

    emit Borrowed(user, amount);
}

function repay(uint256 amount) external {
    address user = _msgSender();
    _settle(user);

    uint256 debt = s_debt[user];
    uint256 paid = amount < debt ? amount : debt;

    I_RIYA_USD.burn(user, paid);
    s_debt[user] = debt - paid;

    // Deliberately does NOT touch s_repaidByYield.
    // Otherwise borrow-$100 / repay-$100 twice buys the top tier for free.
    emit Repaid(user, paid);
}
```

### `burn`, not `burnFrom`

`research/build-plan.md` writes `i_loanToken.burnFrom(msg.sender, paid)`. That is out of
date. Checkpoint 7 decided against `ERC20Burnable` and built `RiyaUSD.burn(from, amount)`
with no allowance, specifically to remove the `approve` transaction from the demo.

So the call is `I_RIYA_USD.burn(user, paid)`, and **this function is the security boundary
that decision relies on.** `RiyaUSD.burn` will destroy anyone's balance on the ledger's
instruction. The only reason that is safe is the line above it: `paid` is capped at the
caller's own debt, and `user` is the caller. `RiyaUSD`'s NatSpec points here. Do not break
that promise.

### `_settle` before the limit check

`borrow` settles first so the limit is checked against debt that already reflects every
proven harvest. Without it, a user who has earned enough yield to clear their debt would
still be blocked by a stale `s_debt`.

### The limit is checked here and nowhere else

`research/ideas.md` calls this "the rule that must not be broken". Every input to it is
Creditcoin state: collateral, score, LTV, and debt. Ethereum can influence a borrow limit
only by proving that a deposit or a harvest happened.

That sentence is worth putting in the submission. It is the cleanest statement of why riya
is a Creditcoin protocol rather than an Ethereum protocol with a Creditcoin frontend.

### Repaying more than you owe

`paid` is capped at `debt`, so overpaying burns only what was owed and the surplus stays in
the user's wallet. Do not revert on it. A user repaying their exact balance when a harvest
lands in the same block would otherwise fail for no good reason.

---

## 8. Events

```solidity
event DebtRetired(address indexed user, uint256 applied, uint256 surplus);
event Borrowed(address indexed user, uint256 amount);
event Repaid(address indexed user, uint256 amount);
```

`DebtRetired` is the one the demo needs. It fires from `_settle`, so it is what shows a
borrower's debt falling because a harvest was proven on the other chain.

Note the asymmetry with `RiyaASC.ProofConsumed`. That event fires once per proof.
`DebtRetired` fires once per user, later, when they next touch the contract. A harvest that
reduces fifty borrowers' debts emits one `ProofConsumed` immediately and fifty
`DebtRetired`s spread over time. Your frontend cannot build a debt history from
`DebtRetired` alone, because a user who never returns never emits one.

---

## 9. The circular deploy, with three contracts

Checkpoint 7 flagged this. Here is the arithmetic.

Three contracts and three dependencies:

| Contract | Needs |
|---|---|
| `RiyaUSD` | the ledger |
| `RiyaASC` | the ledger, plus escrow, adapter, chain key |
| `LoanLedger` | the ASC and the token |

Deploy the ledger last and only one address needs predicting:

```solidity
uint256 nonce = vm.getNonce(deployer);

// The ledger is the third deployment from this nonce, so nonce + 2.
address predictedLedger = vm.computeCreateAddress(deployer, nonce + 2);

riyaUSD = new RiyaUSD(predictedLedger);                        // nonce
asc     = new RiyaASC(chainKey, escrow, adapter, predictedLedger); // nonce + 1
ledger  = new LoanLedger(address(asc), address(riyaUSD));      // nonce + 2

if (address(ledger) != predictedLedger) revert DeployRiya__PredictionFailed();
```

Checkpoint 7's snippet says `nonce + 1`, which is right for two contracts. With three it is
`nonce + 2`. Count the deployments between the prediction and the ledger, not the contracts
in the system.

**Keep the assertion.** A shifted nonce does not fail loudly. It deploys a token and an ASC
that both point at an address where nothing lives, and every mint and every dispatch reverts
forever. The check costs one comparison.

Two more things from `CLAUDE.md`:

- Set `bypass_prevrandao = true` in `foundry.toml`, or `forge script` fails against
  Creditcoin Testnet on missing `prevRandao` in block headers.
- The deployer needs tCTC. This is still open question 5 from checkpoint 5, and it blocks
  this script the same way it blocks the worker.

---

## Tests (checkpoint 9)

Authentication: see the list in section 1. The calldata-suffix test is the one that pins
that whole section.

The accumulator, which is where the real bugs are:

- **first depositor:** a user depositing after `s_yieldPerShare` is already large receives
  nothing from past harvests and has their marker set to the current value. Do not skip
  this one.
- two users with different collateral split a harvest in proportion, and neither one's
  settlement affects the other's
- a user with zero debt accrues the whole pending amount into `s_credit`
- a user whose pending yield exceeds their debt clears the debt and banks the rest
- `_settle` called twice in a row changes nothing the second time
- `onHarvest` with `s_totalCollateral == 0` reverts with `LoanLedger__NoCollateral`
- distributing yield does not require looping: assert the gas cost of `onHarvest` is flat
  across 1, 10, and 100 depositors

The score:

- manual `repay` leaves `s_repaidByYield` untouched, so the score does not move
- borrow, repay in cash, and repeat ten times: the score is still 0
- yield retiring 20% of collateral gives a score of 100 and the 50% tier
- the score is capped at 100 and never exceeds it
- a second deposit lowers the score and raises the absolute borrow limit

Borrowing:

- borrowing exactly at the limit succeeds, one unit over reverts with
  `LoanLedger__ExceedsLimit`
- borrowing mints exactly `amount` in 6-decimal units
- a borrow immediately after an unsettled harvest uses the post-settlement debt
- repaying more than the debt burns only the debt and leaves the surplus in the wallet
- after a proven harvest retires debt, `RiyaUSD.totalSupply()` is **unchanged**. This is the
  invariant from checkpoint 7 and it is the test that will confuse someone reading the suite
  cold. Comment it.

Integration, once the proof fixture builder exists:

- a proven deposit, then a borrow, then a proven harvest, then a check that debt fell
  without any user transaction in between
- two harvests proven out of order produce different results than in order, demonstrating
  why the worker's ordered queue exists

---

**Next:** Checkpoint 9 — the test suite, the `MockAaveSpoke`, and the proof fixture
builder that every ASC test depends on.
