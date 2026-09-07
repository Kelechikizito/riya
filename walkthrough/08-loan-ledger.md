# Checkpoint 8 · `LoanLedger`

> Part of the riya guided build.
>
> **File to create:** `src/destination-chain/LoanLedger.sol` (the stub is already there).
> Design source: `research/build-plan.md` section 3. This checkpoint is the build order,
> with the parts of that plan that have gone out of date corrected.

---

## Build order

1. Errors, constants, state, `onlyASC`
2. `_settle`
3. `onDeposit` and `onHarvest`
4. `score` and `maxLtvBps`
5. `borrow` and `repay`
6. `selfRepayRateBps`
7. The deploy script

---

## 1. The one decision to make first

`LoanLedger` is called two ways, and they authenticate differently:

| Caller | Functions | Identity from |
|---|---|---|
| `RiyaASC` | `onDeposit`, `onHarvest` | `msg.sender` |
| A user | `borrow`, `repay` | `_msgSender()` |

Checkpoint 10 adds sponsored gas by inheriting `ERC2771Context`, which overrides
`_msgSender()` for the whole contract with no per-function granularity. If the ASC path
uses `_msgSender()`, its security stops being one address comparison and starts depending
on the forwarder. Retrofitting means redeploying the contract that holds everyone's
collateral, so the split goes in now.

Until checkpoint 10 there is no forwarder, `_msgSender()` resolves through plain `Context`,
and behaviour is identical. You are buying the seam, not the feature.

```solidity
/// @dev DELIBERATELY `msg.sender`, NOT `_msgSender()`.
///      This path is reached only by `RiyaASC` calling directly, never through a
///      forwarder, and it carries every proof-verified dollar in the system.
///      If a linter or a reviewer asks you to "fix" this for consistency, the answer
///      is no. See walkthrough/08-loan-ledger.md.
modifier onlyASC() {
    if (msg.sender != I_ASC) revert LoanLedger__NotASC();
    _;
}
```

Keep that comment. In a contract inheriting `ERC2771Context`, a bare `msg.sender` looks
like a bug, and "use `_msgSender()` for consistency" is the most natural review comment in
the world. Applying it introduces the vulnerability.

Two smaller rules that come with the pattern:

- Never branch on `msg.data.length`. A forwarded call arrives with 20 extra bytes appended.
- Cache `_msgSender()` in a local at the top of each user function.

---

## 2. State

Three corrections to `build-plan.md` before you copy it across:

- Immutables are `I_ASC` and `I_RIYA_USD`. The repo uses uppercase (`RiyaASC.I_CHAIN_KEY`,
  `RiyaUSD.I_LEDGER`).
- The token type is `RiyaUSD`, not `IMockUSD`. That name predates the contract.
- No `IYieldAdapter` here. The ledger never touches Ethereum.

```solidity
error LoanLedger__NotASC();
error LoanLedger__ExceedsLimit();
error LoanLedger__NoCollateral();
error LoanLedger__ZeroAddress();

uint256 private constant PRECISION = 1e18;
uint256 private constant GRADUATION_TARGET_BPS = 2_000;  // 20% of collateral
uint256 private constant FEE_BPS = 1_500;                // 15%
uint256 private constant BPS_DENOMINATOR = 10_000;

address public immutable I_ASC;
RiyaUSD public immutable I_RIYA_USD;

mapping(address => uint256) public s_collateral;
uint256 public s_totalCollateral;

mapping(address => uint256) public s_debt;
mapping(address => uint256) public s_repaidByYield;  // the score's basis
mapping(address => uint256) public s_credit;         // yield with no debt to retire

uint256 public s_protocolFees;                       // a claim on the Ethereum reserve

uint256 public s_yieldPerShare;
mapping(address => uint256) public s_marker;
```

**Units.** Collateral is 1:1 with the dollars escrowed. There is no share price anywhere in
riya, so collateral, debt, and `RiyaUSD` are all 6-decimal USDC units and nothing ever
converts.

**`PRECISION` is 1e18 and that is correct.** It is not a unit, it is a scaling factor.
`s_yieldPerShare` holds yield per unit of collateral, which is a fraction far below 1.
Without the scalar, 85 USDC across 1,000,000 USDC of collateral divides to zero and every
harvest distributes nothing. The 1e18 cancels out again in `_settle`.

---

## 3. `_settle`

Write this before the functions that call it.

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
            s_repaidByYield[user] += applied;     // score counts proven dollars only
            s_credit[user] += pending - applied;  // surplus when debt is already clear

            emit DebtRetired(user, applied, pending - applied);
        }
    }

    s_marker[user] = acc;
}
```

### How the accumulator works

One proven harvest must reduce every borrower's debt. Looping depositors is O(n) gas, so the
protocol would break at the moment it succeeds. Instead `onHarvest` moves one global number
and each user's share is computed later, when they next touch the contract.

`s_yieldPerShare` is the running total of yield distributed per unit of collateral, ever.
`s_marker[user]` is that number's value at the user's last settlement. The gap between them,
times their collateral, is what they are owed.

Alice has 1,000 collateral, Bob has 3,000, total 4,000. A harvest distributes 400 net:

```
s_yieldPerShare += (400 * 1e18) / 4000 = 1e17
```

Alice next calls `borrow`, so `_settle(alice)` runs:

```
pending = 1000 * (1e17 - 0) / 1e18 = 100
```

She holds a quarter of the collateral and gets a quarter of the yield. Bob's marker is
untouched, so his 300 is still waiting. Nothing looped.

### Three things not to change

**The `if (collateral != 0)` guard.** A new user has `s_marker == 0`, so if
`s_yieldPerShare` is already large the subtraction gives the whole history of the protocol
and they look owed a share of every past harvest. They are not, because on their first
`onDeposit` this guard skips the block and the last line sets their marker to the current
value. This only works because `_settle` runs *before* collateral is added.

**`s_marker[user] = acc` sits outside the `if`.** A user with zero collateral still needs
their marker brought up to date, or they inherit a stale marker on their first deposit and
claim history they missed.

**Call `_settle(user)` before touching `s_collateral[user]` or `s_debt[user]`.** Every time,
in `onDeposit`, `borrow`, and `repay`. `onHarvest` is the exception because it changes no
single user's position.

Calling `_settle` twice in a row is safe: the second call finds a zero gap.

---

## 4. `onDeposit` and `onHarvest`

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

Both signatures are fixed by `src/interfaces/ILoanLedger.sol` and already called by
`RiyaASC._dispatch`. They cannot change.

**`s_protocolFees` is a number, not money.** It is a claim on USDC in the Ethereum escrow,
and it becomes spendable only with writability. Say so in the NatSpec.

**The division truncates.** The remainder stays in the contract unclaimable. It is far below
one millionth of a cent per harvest, so it needs no handling, but do not write a test
asserting the distributed total equals `gross - fee` exactly.

**`LoanLedger__NoCollateral` needs a matching change in the worker.** That error is not in
`offchain/src/worker.ts`'s `PERMANENT_ERRORS` set, so the worker retries it forever, and
because the ordered queue stops on a retriable failure it blocks every later event. Only
reachable if a deposit proof is dead-lettered while the harvest behind it is not. Add the
error to that set rather than softening the revert, since an early return would lose the
yield with no record.

---

## 5. `score` and `maxLtvBps`

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

The score measures how much debt yield has retired, against a target of 20% of collateral.

**Only `_settle` writes `s_repaidByYield`.** `repay` must not touch it. If it did, borrowing
$100 and repaying $100 in cash on repeat would buy the top tier without ever letting yield
work.

**The score is relative to current collateral**, so a second deposit lowers it while raising
the absolute borrow limit. Leave the behaviour; label it in the frontend.

---

## 6. `borrow` and `repay`

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

**`burn`, not `burnFrom`.** `build-plan.md` is out of date here. Checkpoint 7 dropped
`ERC20Burnable` and built `RiyaUSD.burn(from, amount)` with no allowance, to remove the
`approve` step.

**`repay` is the security boundary for that decision.** `RiyaUSD.burn` will destroy anyone's
balance on the ledger's instruction, and the only thing making that safe is this function
capping `paid` at the caller's own debt and passing the caller as `from`. `RiyaUSD`'s NatSpec
points here.

**`_settle` before the limit check**, or a user who has earned enough yield to clear their
debt is still blocked by a stale `s_debt`.

**Cap, do not revert, on overpayment.** A user repaying their exact balance when a harvest
lands in the same block would otherwise fail for no reason.

The limit is checked in `borrow` and nowhere else. Every input to it is Creditcoin state.

---

## 7. `selfRepayRateBps`

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

No oracle. The frontend passes the observed Aave APY and computes
`yearsToZero = 10_000 / selfRepayRateBps`.

---

## 8. Events

```solidity
event DebtRetired(address indexed user, uint256 applied, uint256 surplus);
event Borrowed(address indexed user, uint256 amount);
event Repaid(address indexed user, uint256 amount);
```

`DebtRetired` fires from `_settle`, so it fires once per user when they next touch the
contract, not when the harvest lands. A harvest reducing fifty debts emits one
`RiyaASC.ProofConsumed` immediately and fifty `DebtRetired`s spread over time. A user who
never returns never emits one, so the frontend cannot build a full debt history from this
event alone.

---

## 9. The deploy script

Three contracts, three dependencies:

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

riyaUSD = new RiyaUSD(predictedLedger);                            // nonce
asc     = new RiyaASC(chainKey, escrow, adapter, predictedLedger); // nonce + 1
ledger  = new LoanLedger(address(asc), address(riyaUSD));          // nonce + 2

if (address(ledger) != predictedLedger) revert DeployRiya__PredictionFailed();
```

Checkpoint 7's snippet says `nonce + 1`, which is right for two contracts. Count the
deployments between the prediction and the ledger, not the contracts in the system.

Keep the assertion. A shifted nonce does not fail loudly; it deploys a token and an ASC
pointing at an empty address, and every mint and dispatch reverts forever.

Set `bypass_prevrandao = true` in `foundry.toml` or `forge script` fails against Creditcoin
Testnet. The deployer needs tCTC, which is still open question 5 from checkpoint 5.

---

## Tests (checkpoint 9)

Authentication:

- `onDeposit` / `onHarvest` from a non-ASC address reverts with `LoanLedger__NotASC`
- the same call with 20 bytes of address appended to the calldata still reverts. This pins
  section 1 and must keep passing through checkpoint 10.
- `borrow` / `repay` attribute the position to `msg.sender` while no forwarder exists

The accumulator, where the real bugs are:

- **first depositor:** a user depositing after `s_yieldPerShare` is already large receives
  nothing from past harvests and has their marker set to the current value. Do not skip this
  one.
- two users with different collateral split a harvest in proportion, and neither one's
  settlement affects the other's
- a user with zero debt accrues the whole pending amount into `s_credit`
- pending yield exceeding debt clears the debt and banks the rest
- `_settle` twice in a row changes nothing the second time
- `onHarvest` with zero total collateral reverts with `LoanLedger__NoCollateral`
- `onHarvest` gas is flat across 1, 10, and 100 depositors

The score:

- manual `repay` leaves `s_repaidByYield` untouched
- borrow and repay in cash ten times: the score is still 0
- yield retiring 20% of collateral gives a score of 100 and the 50% tier
- the score caps at 100
- a second deposit lowers the score and raises the absolute borrow limit

Borrowing:

- borrowing exactly at the limit succeeds, one unit over reverts with
  `LoanLedger__ExceedsLimit`
- `borrow` mints exactly `amount` in 6-decimal units
- a borrow right after an unsettled harvest uses the post-settlement debt
- repaying more than the debt burns only the debt
- after a proven harvest retires debt, `RiyaUSD.totalSupply()` is unchanged. This is the
  invariant from checkpoint 7. Comment the test.

Integration, once the proof fixture builder exists:

- proven deposit, borrow, proven harvest, then debt falls with no user transaction between
- two harvests proven out of order give different results than in order

---

**Next:** Checkpoint 9 — the test suite, the `MockAaveSpoke`, and the proof fixture
builder that every ASC test depends on.
