# Implementing the Alchemix borrows

Build order for §3 of `alchemix.md`. Each step is independently shippable.

Snippets omit section banners (`headers`), NatSpec, and imports. Errors follow
the house style: `if/revert`, `Contract__Error`.

| # | Step | Effort | §  |
|---|---|---|---|
| 0 | Fix the build | 1 min | — |
| — | Where `AaveV4Adapter` fits | read first | — |
| 1 | `RiyaVault` — shared ERC-4626 | ~120 LoC | 3.1 |
| 2 | Harvest + performance fee | ~30 LoC | 3.2 |
| 3 | `LoanLedger` — mirrored shares, pro-rata yield | ~150 LoC | 3.1 |
| 4 | `RiyaASC` — decode, guard, dispatch | ~90 LoC | — |
| 5 | Manual repayment (score-neutral) | ~10 LoC | 3.4 |
| 6 | Self-repay rate view | ~8 LoC | 3.3 |
| 7 | Position NFT | ~40 LoC | 3.5 |
| 8 | `IYieldAdapter` seam | ~20 LoC | 3.6 |

---

## 0. Fix the build

`AaveV4Adapter.sol` declares `TokensDeposited` / `TokensWithdrawn` but emits
`Deposited` / `Withdrawn`. `forge build` fails. Rename the declarations to match
the emits — steps 1–4 depend on those event signatures.

---

## Where `AaveV4Adapter` fits

It is riya's strategy leg, and it barely changes. `RiyaVault` sits on top of it;
the adapter never learns that Creditcoin exists.

```
USDC ─▶ RiyaVault ─▶ AaveV4Adapter ─▶ Aave V4 Spoke      [Ethereum]
          │  ERC-4626      │  strategy
          │  shares, fee   │  principal / yield split
          │
          └─ emits Deposit, Harvested
                   │
              watcher ─▶ RiyaASC ─▶ LoanLedger           [Creditcoin]
```

### Four changes

| Change | Why |
|---|---|
| `harvest()` gains `onlyVault` | The vault becomes the entrypoint — it knows `totalSupply()` and takes the fee. Permissionlessness moves up one layer: `RiyaVault.harvest()` is open to anyone. |
| Add a `principal()` view | The vault's `totalAssets()` must read principal, not principal + yield. See below. |
| Rename event `Harvested` → `YieldPulled` | Stops two events called `Harvested` appearing in one proven transaction. |
| Size `i_minHarvest` on gross | The vault takes 15% after; net delivered is 0.85 × the floor. |

### The correction this forces

Step 1 as first written had `totalAssets()` return `i_adapter.totalAssets()` —
which is principal **plus unharvested yield**. Share price would drift up between
harvests and drop at each one, inflating borrow limits in between. It must be:

```solidity
function totalAssets() public view override returns (uint256) {
    return i_adapter.principal();      // NOT i_adapter.totalAssets()
}
```

`s_principal` moves only on deposit and withdraw, by exactly the assets moved, so
share price stays exactly 1 — which is what step 1 claims. The adapter's three
views now have distinct jobs:

| View | Reads | Consumer |
|---|---|---|
| `principal()` | `s_principal` | Vault `totalAssets()` → collateral, share price, borrow limits |
| `totalAssets()` | Aave's supplied balance | `yieldAccrued()` |
| `yieldAccrued()` | the difference, clamped at 0 | The `i_minHarvest` gate, and what `harvest()` pulls |

One line to add (`s_principal` itself is unchanged):

```solidity
function principal() external view returns (uint256) { return s_principal; }
```

### What does not change

- **`deposit()`** already pulls with `safeTransferFrom(i_vault, ...)`, which is
  exactly what the vault's `forceApprove` + call expects. No edit.
- **`yieldAccrued()`**'s clamp already covers an Aave deficit. Worth naming what
  that case means downstream: `principal()` then reports more collateral than
  exists. That is the bad-debt scenario, and the step-2 reserve is its backstop.
- **The event the ASC proves is the vault's**, not the adapter's. Their
  signatures differ, so they cannot collide — but the rename keeps it obvious to
  a reader why `log.address_ == i_sourceVault` is the check that matters.

### `withdraw()` has no caller in v1

The vault disables withdrawals and nothing else is `onlyVault`, so the function
is unreachable. Leave it that way rather than adding an owner-gated escape hatch
— that is a rug vector a judge will look for, and `edge_case.md` already frames
the lock as the security model. Still test it: it is the phase-2 path.

### `IVault.sol` is empty

The adapter needs nothing from it — `onlyVault` is an address compare. Fill it
with the vault's surface for scripts and tests, not for the adapter.

---

## 1. `RiyaVault` — the shared ERC-4626

`src/source-chain/ethereum/RiyaVault.sol`. This is riya's MYT.

**Three deliberate restrictions**, each load-bearing:

| Restriction | Why |
|---|---|
| Shares non-transferable | A share transfer on Ethereum desyncs the Creditcoin mirror — debt with no collateral. |
| Withdrawals disabled | Releasing collateral needs the Creditcoin debt state. That is the writability gap `edge_case.md` already accepts. |
| `totalAssets()` = adapter only | Harvested yield must **not** raise share price — see step 2. |

```solidity
contract RiyaVault is ERC4626 {
    error RiyaVault__SharesNonTransferable();
    error RiyaVault__WithdrawalsDisabled();
    error RiyaVault__BelowMinDeposit();

    IYieldAdapter public immutable i_adapter;
    uint256 public immutable i_minDeposit;

    function totalAssets() public view override returns (uint256) {
        return i_adapter.principal();   // principal only — see "Where AaveV4Adapter fits"
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal override
    {
        if (assets < i_minDeposit) revert RiyaVault__BelowMinDeposit();
        super._deposit(caller, receiver, assets, shares);  // pulls assets, mints shares
        IERC20(asset()).forceApprove(address(i_adapter), assets);
        i_adapter.deposit(assets);                          // push straight to Aave
    }

    function maxWithdraw(address) public pure override returns (uint256) { return 0; }
    function maxRedeem(address)   public pure override returns (uint256) { return 0; }

    function _withdraw(address, address, address, uint256, uint256) internal pure override {
        revert RiyaVault__WithdrawalsDisabled();
    }

    /// @dev Mint and burn only. Blocks secondary transfer of collateral claims.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert RiyaVault__SharesNonTransferable();
        super._update(from, to, value);
    }
}
```

**The event the watcher proves for deposits is ERC-4626's own** — no custom event
needed:

```
Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)
```

`owner` is the depositor's Ethereum address; the demo uses the same address on
Creditcoin (both EVM). Note it in the submission.

**Share price is pinned at 1:1** because yield never re-enters `totalAssets()`.
A plain `mapping(address => uint256)` would do the same job — ERC-4626 is chosen
for standard tooling and because it is the seam a multi-strategy allocator plugs
into later (§3.6). Say that rather than implying share price floats.

---

## 2. Harvest + performance fee

Move the harvest entrypoint from the adapter to the vault: the vault knows
`totalSupply()`, which the Creditcoin ledger needs.

**In `AaveV4Adapter`:** add `onlyVault` to `harvest()`. Nothing else changes.

**In `RiyaVault`:**

```solidity
uint256 public constant FEE_BPS = 1_500;   // 15%, matching Alchemix's MYT fee
address public immutable i_treasury;
uint256 public s_harvestNonce;

event Harvested(uint256 netYield, uint256 fee, uint256 totalShares, uint256 nonce);

function harvest() external returns (uint256 net) {
    uint256 gross = i_adapter.harvest();          // adapter transfers assets to this vault
    uint256 fee = (gross * FEE_BPS) / 10_000;
    net = gross - fee;
    if (fee != 0) IERC20(asset()).safeTransfer(i_treasury, fee);
    emit Harvested(net, fee, totalSupply(), ++s_harvestNonce);
}
```

Permissionless, as the adapter's already is. `i_minHarvest` in the adapter still
gates dust.

**Where the net yield goes.** It stays in the vault as protocol reserve on
Ethereum. It is *not* returned to depositors and *not* added to `totalAssets()` —
the depositor is compensated on Creditcoin by debt reduction. Counting it on both
sides would pay twice. That reserve is also the bad-debt backstop from §4.3.

**Fee is taken before the event**, so the proven number is already net. Rule 1
holds: value moves, then the event fires.

---

## 3. `LoanLedger` on Creditcoin

Distributes yield pro-rata **without looping depositors** — the MasterChef
accumulator, applied to a share ledger mirrored from Ethereum.

```solidity
contract LoanLedger {
    error LoanLedger__NotASC();
    error LoanLedger__ExceedsLimit();
    error LoanLedger__NoShares();

    uint256 private constant PRECISION = 1e18;
    uint256 private constant GRADUATION_TARGET_BPS = 2_000;   // 20% of collateral

    address public immutable i_asc;
    IMockUSD public immutable i_loanToken;

    // --- mirror of the source-chain vault ---
    mapping(address => uint256) public s_shares;
    uint256 public s_totalShares;

    // --- per-user position ---
    mapping(address => uint256) public s_debt;
    mapping(address => uint256) public s_repaidByYield;   // score basis
    mapping(address => uint256) public s_credit;          // yield with no debt to retire

    // --- pro-rata accumulator ---
    uint256 public s_yieldPerShare;
    mapping(address => uint256) public s_marker;

    modifier onlyASC() { if (msg.sender != i_asc) revert LoanLedger__NotASC(); _; }
```

**Mirror updates** — driven only by proven source-chain events:

```solidity
    function onDeposit(address user, uint256 shares) external onlyASC {
        _settle(user);
        s_shares[user] += shares;
        s_totalShares  += shares;
    }

    function onHarvest(uint256 netYield, uint256 totalSharesAtSource) external onlyASC {
        if (s_totalShares == 0) revert LoanLedger__NoShares();
        // Drift guard: the mirror must match the vault at harvest time.
        if (s_totalShares != totalSharesAtSource) revert LoanLedger__MirrorDrift();
        s_yieldPerShare += (netYield * PRECISION) / s_totalShares;
    }
```

The drift guard is cheap and turns a silent accounting bug into a revert. It
fails if a deposit proof is still in flight — the watcher retries in order.

**Settlement** — this is where debt actually falls, and the only place the score
moves:

```solidity
    function _settle(address user) internal {
        uint256 shares = s_shares[user];
        uint256 acc = s_yieldPerShare;
        if (shares != 0) {
            uint256 pending = (shares * (acc - s_marker[user])) / PRECISION;
            if (pending != 0) {
                uint256 debt = s_debt[user];
                uint256 applied = pending < debt ? pending : debt;
                s_debt[user] = debt - applied;
                s_repaidByYield[user] += applied;      // score: proven dollars only
                s_credit[user] += pending - applied;   // surplus, per ideas.md
                emit DebtRetired(user, applied, pending - applied);
            }
        }
        s_marker[user] = acc;
    }
```

The `s_credit` line implements `ideas.md`'s "yield arriving with no outstanding
debt accrues as a withdrawable balance" for free.

**Score and ladder:**

```solidity
    function score(address user) public view returns (uint256) {
        uint256 target = (s_shares[user] * GRADUATION_TARGET_BPS) / 10_000;
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

Shares are 1:1 with dollars (step 1), so `s_shares` doubles as the collateral
figure. If share price ever floats, this needs a stored asset value.

**Borrow:**

```solidity
    function borrow(uint256 amount) external {
        _settle(msg.sender);
        uint256 limit = (s_shares[msg.sender] * maxLtvBps(msg.sender)) / 10_000;
        if (s_debt[msg.sender] + amount > limit) revert LoanLedger__ExceedsLimit();
        s_debt[msg.sender] += amount;
        i_loanToken.mint(msg.sender, amount);
    }
```

The limit is checked here and nowhere else — `ideas.md`'s "rule that must not be
broken".

---

## 4. `RiyaASC`

Fills in `src/ASC.sol`. Verify → check status → check origin → dispatch.

```solidity
contract RiyaASC {
    error RiyaASC__AlreadyConsumed();
    error RiyaASC__ProofInvalid();
    error RiyaASC__TxReverted();
    error RiyaASC__NoRelevantLog();

    bytes32 private constant DEPOSIT_SIG   = keccak256("Deposit(address,address,uint256,uint256)");
    bytes32 private constant HARVESTED_SIG = keccak256("Harvested(uint256,uint256,uint256,uint256)");

    address public immutable i_sourceVault;   // RiyaVault on Sepolia
    uint64  public immutable i_chainKey;
    LoanLedger public immutable i_ledger;

    mapping(bytes32 => bool) private s_consumed;

    function submit(
        uint64 height,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external {
        INativeQueryVerifier v = NativeQueryVerifierLib.getVerifier();

        // Rule 2: one proof, one use.
        bytes32 key = keccak256(
            abi.encode(i_chainKey, height, merkleProof.root, v.calculateTxIndex(merkleProof))
        );
        if (s_consumed[key]) revert RiyaASC__AlreadyConsumed();
        s_consumed[key] = true;

        if (!v.verifyAndEmit(i_chainKey, height, encodedTransaction, merkleProof, continuityProof)) {
            revert RiyaASC__ProofInvalid();
        }

        // Inclusion is not success.
        EvmV1Decoder.ReceiptFields memory r = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (r.receiptStatus != 1) revert RiyaASC__TxReverted();

        _dispatch(r);
    }
```

```solidity
    function _dispatch(EvmV1Decoder.ReceiptFields memory r) internal {
        bool handled;

        EvmV1Decoder.LogEntry[] memory harvests =
            EvmV1Decoder.getLogsByEventSignature(r, HARVESTED_SIG);
        for (uint256 i; i < harvests.length; ++i) {
            // Anyone can emit an identically-shaped event. Pin the emitter.
            if (harvests[i].address_ != i_sourceVault) continue;
            (uint256 net,, uint256 totalShares,) =
                abi.decode(harvests[i].data, (uint256, uint256, uint256, uint256));
            i_ledger.onHarvest(net, totalShares);
            handled = true;
        }

        EvmV1Decoder.LogEntry[] memory deposits =
            EvmV1Decoder.getLogsByEventSignature(r, DEPOSIT_SIG);
        for (uint256 i; i < deposits.length; ++i) {
            if (deposits[i].address_ != i_sourceVault) continue;
            address owner = address(uint160(uint256(deposits[i].topics[2])));
            (, uint256 shares) = abi.decode(deposits[i].data, (uint256, uint256));
            i_ledger.onDeposit(owner, shares);
            handled = true;
        }

        if (!handled) revert RiyaASC__NoRelevantLog();
    }
}
```

Three checks carry the security: the replay key, `receiptStatus == 1`, and
`log.address_ == i_sourceVault`. Dropping any one is exploitable.

The `MerkleProof` / `ContinuityProof` structs replace the flattened parameter
list currently in `src/ASC.sol` — that is what the precompile's interface
actually takes.

---

## 5. Manual repayment — score-neutral

```solidity
    function repay(uint256 amount) external {
        _settle(msg.sender);
        uint256 debt = s_debt[msg.sender];
        uint256 paid = amount < debt ? amount : debt;
        i_loanToken.burnFrom(msg.sender, paid);
        s_debt[msg.sender] = debt - paid;
        emit Repaid(msg.sender, paid);
        // Deliberately does NOT touch s_repaidByYield.
        // Otherwise borrow-$100 / repay-$100 twice buys the top tier for free.
    }
```

One comment does the security work here. Keep it in the code.

---

## 6. Self-repay rate

No oracle: the frontend passes the observed APY.

```solidity
    /// @return bps Share of current debt retired per year at `yieldRateBps`.
    function selfRepayRateBps(address user, uint256 yieldRateBps)
        external view returns (uint256 bps)
    {
        uint256 debt = s_debt[user];
        if (debt == 0) return 0;
        return (s_shares[user] * yieldRateBps) / debt;
    }
```

Frontend: `yearsToZero = 10_000 / selfRepayRateBps`. Put both next to the score
dial — that is what makes the ladder read as a speed trade-off rather than
gatekeeping.

---

## 7. Position NFT

Last, and optional. Re-key the ledger from `address` to `uint256 tokenId`:

```solidity
contract LoanLedger is ERC721 {
    mapping(uint256 => uint256) public s_shares;   // was mapping(address => ...)
    mapping(uint256 => uint256) public s_debt;
    mapping(uint256 => uint256) public s_repaidByYield;
    mapping(uint256 => uint256) public s_marker;

    mapping(address => uint256) public s_positionOf;   // one position per depositor, v1

    function onDeposit(address user, uint256 shares) external onlyASC {
        uint256 id = s_positionOf[user];
        if (id == 0) { id = ++s_nextId; s_positionOf[user] = id; _mint(user, id); }
        _settle(id);
        s_shares[id] += shares;
        s_totalShares += shares;
    }
}
```

**Unresolved:** the score rides on the position, so selling the NFT sells the
repayment record. Either make it soulbound in v1 (`_update` guard, as in step 1)
or accept it and say so. Do not ship it undecided.

---

## 8. `IYieldAdapter`

Extract from `AaveV4Adapter`'s existing surface. Costs nothing, and it is the
concrete thing behind the multi-strategy roadmap claim.

```solidity
interface IYieldAdapter {
    function deposit(uint256 amount) external returns (uint256 assets);
    function withdraw(uint256 amount, address to) external returns (uint256 assets);
    function harvest() external returns (uint256 assets);
    function principal() external view returns (uint256);    // collateral basis
    function totalAssets() external view returns (uint256);  // principal + unharvested yield
    function yieldAccrued() external view returns (uint256);
}
```

`RiyaVault` holds `IYieldAdapter`, never `AaveV4Adapter`. Populate `IVault.sol`
(currently empty) with the vault's own surface for the adapter's `onlyVault` side.

---

## Demo sequence this enables

1. Two wallets deposit into `RiyaVault` → two `Deposit` events → one proof each →
   mirror populated on Creditcoin.
2. Both borrow at 10%.
3. `RiyaVault.harvest()` → **one** transaction, **one** proof → both debts fall
   pro-rata. *This is the shot: one proof, N borrowers.*
4. Wallet A calls `repay()` → debt clears, score does not move. Shows the two
   paths are different on purpose.
5. Another harvest crosses wallet B's tier → limit jumps → B redraws.

Step 3 is the argument for §3.1 and the only frame in which the mainnet
economics work.

## Test checklist

- Share transfer reverts; withdraw reverts.
- `totalAssets()` unchanged by a harvest.
- Harvest with mirror drift reverts.
- Two depositors, one harvest → split exactly pro-rata; no dust loss.
- Pending yield above outstanding debt → surplus lands in `s_credit`.
- Same proof twice → `RiyaASC__AlreadyConsumed`.
- Reverted source tx (`status == 0`) → rejected.
- `Harvested` emitted by an impostor contract → ignored.
- Borrow above limit reverts; borrow at exactly the limit succeeds.
- Borrow/repay loop does not raise the score.
