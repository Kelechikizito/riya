# Implementing the Alchemix borrows

Build order for §3 of `alchemix.md`. Each step is independently shippable.

Snippets omit section banners (`headers`), NatSpec, and imports. Errors follow
the house style: `if/revert`, `Contract__Error`.

**Governing constraint: the source chain holds value and emits facts. It decides
nothing.** Every rule — collateral accounting, the fee, LTV, the score, debt — is
Creditcoin state. Ethereum runs two contracts with no policy in either: an escrow
that forwards deposits, and an adapter that talks to Aave. If a change would put
a business decision on Ethereum, it is the wrong change.

Three things follow, and they shape steps 1–4:

- **Cheaper.** Mainnet gas is the binding constraint (`CLAUDE.md`), and every
  parameter on Ethereum is a storage write nobody needs.
- **Safer.** State that exists once cannot desync. Deleting the Ethereum share
  table removes the mirror-drift bug class instead of guarding it.
- **Better aligned.** "Could this ship on any L2 unchanged?" is the red flag to
  avoid. A generic ERC-4626 vault answers yes; an escrow whose accounting only
  exists on Creditcoin answers no.

| # | Step | Effort | §  |
|---|---|---|---|
| 0 | Fix the build | done | — |
| — | Where `AaveV4Adapter` fits | read first | — |
| 1 | `RiyaEscrow` — custody only | ~40 LoC | 3.1 |
| 2 | Performance fee (Creditcoin-side) | 0 LoC on Ethereum | 3.2 |
| 3 | `LoanLedger` — collateral, fee, pro-rata yield | ~160 LoC | 3.1 |
| 4 | `RiyaASC` — decode, guard, dispatch | ~90 LoC | — |
| 5 | Manual repayment (score-neutral) | ~10 LoC | 3.4 |
| 6 | Self-repay rate view | ~8 LoC | 3.3 |
| 7 | Position NFT | ~40 LoC | 3.5 |
| 8 | `IYieldAdapter` seam | ~20 LoC | 3.6 |

---

## 0. Fix the build — done

`AaveV4Adapter.sol` declared `TokensDeposited` / `TokensWithdrawn` but emitted
`Deposited` / `Withdrawn`, so `forge build` failed. Declarations renamed back to
`Deposited` / `Withdrawn` (commit `fa5c2ed`); steps 1–4 assume those signatures.
The empty `src/interfaces/IVault.sol` was removed at the same time — step 8
recreates it.

---

## Where `AaveV4Adapter` fits

It is riya's strategy leg, and **nothing in it changes**. `RiyaEscrow` sits on
top of it; the adapter never learns that Creditcoin exists.

```
USDC ─▶ RiyaEscrow ─▶ AaveV4Adapter ─▶ Aave V4 Spoke     [Ethereum]
          │ custody         │ principal / yield split
          │ 2 events        │
          └────────┬────────┘
              watcher ─▶ RiyaASC ─▶ LoanLedger           [Creditcoin]
                                    shares · fee · debt
                                    LTV · score
```

Ethereum holds the money and says what happened. Creditcoin decides what it
means. The line between them is the proof, and everything that is a *decision*
sits on the Creditcoin side of it.

### Why no changes

An earlier draft of this plan had four: `onlyVault` on `harvest()`, a
`principal()` view, renaming `Harvested` → `YieldPulled`, and sizing
`i_minHarvest` on gross. All four existed to serve share-price maths and a fee
split on Ethereum. Both moved to Creditcoin (steps 1–3), so all four are gone:

| Dropped change | Why it evaporated |
|---|---|
| `harvest()` gains `onlyVault` | It only needed gating because the vault wrapped it to take a fee. No fee on Ethereum ⇒ leave it permissionless, as written. |
| Add a `principal()` view | It existed so the vault's `totalAssets()` could pin share price. No shares on Ethereum ⇒ no consumer. |
| Rename `Harvested` → `YieldPulled` | The collision was with the *vault's* `Harvested`. The escrow emits no harvest event; the adapter's is the one proven. |
| Size `i_minHarvest` on gross | Gross is all there is now. The floor means what it says. |

`s_principal` stays: `yieldAccrued()` needs it to tell principal from yield, and
that is mechanical bookkeeping, not policy. `i_minHarvest` stays for the same
reason — it guards a real mainnet transaction against dust, which is an
operational limit on the source chain, not a business rule about who gets what.

### What the adapter already gets right

- **`deposit()`** pulls with `safeTransferFrom(i_vault, ...)`, which is exactly
  what the escrow's `forceApprove` + call expects. `i_vault` is the escrow.
- **`harvest()`** transfers yield to the escrow *before* emitting, so a
  successful transaction means the money moved. That ordering is what the ASC
  relies on — keep it.
- **`yieldAccrued()`**'s clamp covers an Aave deficit. Named downstream: the
  Creditcoin ledger then credits less yield than the collateral implies. That is
  the bad-debt scenario, and the step-3 reserve is its backstop.
- **`withdraw()` has no caller in v1.** Nothing but the escrow is `onlyVault` and
  the escrow never withdraws, so it is unreachable. Leave it that way rather than
  adding an owner-gated escape hatch — that is a rug vector a judge will look
  for, and `edge_case.md` frames the lock as the security model. Still test it:
  it is the phase-2 path.

---

## 1. `RiyaEscrow` — custody only

`src/source-chain/ethereum/RiyaEscrow.sol`. **Not** an ERC-4626 vault. It takes
USDC, forwards it to the adapter, and emits one event. That is the whole job.

```solidity
contract RiyaEscrow {
    error RiyaEscrow__BelowMinDeposit();

    IERC20 public immutable i_asset;
    IYieldAdapter public immutable i_adapter;
    uint256 public immutable i_minDeposit;

    /// @notice The event the watcher proves for deposits.
    event Deposited(address indexed user, uint256 assets);

    function deposit(uint256 assets) external {
        if (assets < i_minDeposit) revert RiyaEscrow__BelowMinDeposit();
        i_asset.safeTransferFrom(msg.sender, address(this), assets);
        i_asset.forceApprove(address(i_adapter), assets);
        i_adapter.deposit(assets);
        emit Deposited(msg.sender, assets);
    }
}
```

No shares, no `totalAssets()`, no withdraw, no transfer hook, no owner. It also
holds harvested yield, which the adapter pushes here — that idle balance is the
protocol reserve and the bad-debt backstop.

`user` is the depositor's Ethereum address; the demo uses the same address on
Creditcoin (both EVM). Note it in the submission.

### Why ERC-4626 came out

The earlier draft made this an ERC-4626 vault with non-transferable shares,
withdrawals disabled, and `totalAssets()` pinned so share price stayed exactly 1.
Every one of those is a restriction *undoing* something the standard provides.
Shares that cannot move, cannot be redeemed, and never change price are not
shares — and a 4626 indexer reading it would advertise a redeemable vault that
is not redeemable.

The real ledger was always on Creditcoin. Deleting the Ethereum half removes the
mirror-desync class of bug outright instead of guarding against it: there is no
second copy of the share table to drift.

What is lost is the "standard tooling" argument and the multi-strategy seam. The
seam survives — it is `IYieldAdapter` behind a stable escrow address (step 8) —
and if a transferable share token is ever wanted, it belongs on Creditcoin, where
the accounting actually lives.

---

## 2. Performance fee — moved to Creditcoin

There is no fee code on Ethereum. `harvest()` on the adapter stays exactly as
committed: permissionless, moves gross yield into the escrow, emits

```
Harvested(address indexed caller, uint256 assets)
```

The 15% split happens in `LoanLedger.onHarvest` (step 3) against the proven gross
number.

**Why this is free.** The fee was already notional. Net yield "stays in the vault
as protocol reserve" and the fee went to a treasury address — but neither is
distributed in v1 and both sit in Ethereum contracts nobody can withdraw from.
Splitting on Ethereum bought nothing and cost a storage write plus an ERC-20
transfer on every mainnet harvest.

Accruing it on Creditcoin instead makes the fee a bookkeeping claim on the
Ethereum reserve, realisable in phase 2 when withdrawals exist. Same economics,
one less source-chain transfer, and the fee rate becomes a Creditcoin-side
parameter — changeable without touching a deployed Ethereum contract.

**What also went away:** `s_harvestNonce`. The ASC already dedupes on the proof
key (chain, height, root, tx index), so a source-chain nonce was a second replay
guard doing the first one's job — and a mainnet storage write per harvest.

---

## 3. `LoanLedger` on Creditcoin

Now the only ledger in the system. It owns collateral, the fee, debt, the score,
and the LTV ladder. Distributes yield pro-rata **without looping depositors** —
the MasterChef accumulator.

```solidity
contract LoanLedger {
    error LoanLedger__NotASC();
    error LoanLedger__ExceedsLimit();
    error LoanLedger__NoCollateral();

    uint256 private constant PRECISION = 1e18;
    uint256 private constant GRADUATION_TARGET_BPS = 2_000;   // 20% of collateral
    uint256 private constant FEE_BPS = 1_500;                 // 15%, matching Alchemix's MYT fee

    address public immutable i_asc;
    IMockUSD public immutable i_loanToken;

    // --- collateral, credited from proven source-chain deposits ---
    mapping(address => uint256) public s_collateral;
    uint256 public s_totalCollateral;

    // --- per-user position ---
    mapping(address => uint256) public s_debt;
    mapping(address => uint256) public s_repaidByYield;   // score basis
    mapping(address => uint256) public s_credit;          // yield with no debt to retire

    // --- protocol ---
    uint256 public s_protocolFees;                        // claim on the Ethereum reserve

    // --- pro-rata accumulator ---
    uint256 public s_yieldPerShare;
    mapping(address => uint256) public s_marker;

    modifier onlyASC() { if (msg.sender != i_asc) revert LoanLedger__NotASC(); _; }
```

Collateral is denominated in the source asset, 1:1 with the dollars escrowed —
there is no share price anywhere in the system to float.

**Mirror updates** — driven only by proven source-chain events:

```solidity
    function onDeposit(address user, uint256 assets) external onlyASC {
        _settle(user);
        s_collateral[user] += assets;
        s_totalCollateral  += assets;
    }

    function onHarvest(uint256 gross) external onlyASC {
        if (s_totalCollateral == 0) revert LoanLedger__NoCollateral();
        uint256 fee = (gross * FEE_BPS) / 10_000;
        s_protocolFees += fee;
        s_yieldPerShare += ((gross - fee) * PRECISION) / s_totalCollateral;
    }
```

The old draft passed `totalSharesAtSource` alongside and reverted on mismatch — a
drift guard against the Ethereum share table diverging from the mirror. There is
no Ethereum share table any more, so there is nothing to drift and no guard to
write. Ordering still matters (a deposit proof landing after a harvest earns no
share of it), and that is the watcher's job: submit in source-chain order.

**Settlement** — where debt actually falls, and the only place the score moves:

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
        uint256 target = (s_collateral[user] * GRADUATION_TARGET_BPS) / 10_000;
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

**Borrow:**

```solidity
    function borrow(uint256 amount) external {
        _settle(msg.sender);
        uint256 limit = (s_collateral[msg.sender] * maxLtvBps(msg.sender)) / 10_000;
        if (s_debt[msg.sender] + amount > limit) revert LoanLedger__ExceedsLimit();
        s_debt[msg.sender] += amount;
        i_loanToken.mint(msg.sender, amount);
    }
```

The limit is checked here and nowhere else — `ideas.md`'s "rule that must not be
broken". Note that every input to it (collateral, score, LTV, debt) is now
Creditcoin state. Ethereum cannot influence a borrow limit except by proving that
a deposit or a harvest happened.

---

## 4. `RiyaASC`

Fills in `src/ASC.sol`. Verify → check status → check origin → dispatch.

```solidity
contract RiyaASC {
    error RiyaASC__AlreadyConsumed();
    error RiyaASC__ProofInvalid();
    error RiyaASC__TxReverted();
    error RiyaASC__NoRelevantLog();

    bytes32 private constant DEPOSIT_SIG   = keccak256("Deposited(address,uint256)");
    bytes32 private constant HARVESTED_SIG = keccak256("Harvested(address,uint256)");

    address public immutable i_escrow;        // RiyaEscrow on Sepolia
    address public immutable i_adapter;       // AaveV4Adapter on Sepolia
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
            if (harvests[i].address_ != i_adapter) continue;
            uint256 gross = abi.decode(harvests[i].data, (uint256));
            i_ledger.onHarvest(gross);
            handled = true;
        }

        EvmV1Decoder.LogEntry[] memory deposits =
            EvmV1Decoder.getLogsByEventSignature(r, DEPOSIT_SIG);
        for (uint256 i; i < deposits.length; ++i) {
            if (deposits[i].address_ != i_escrow) continue;
            address user = address(uint160(uint256(deposits[i].topics[1])));
            uint256 assets = abi.decode(deposits[i].data, (uint256));
            i_ledger.onDeposit(user, assets);
            handled = true;
        }

        if (!handled) revert RiyaASC__NoRelevantLog();
    }
}
```

Three checks carry the security: the replay key, `receiptStatus == 1`, and the
`log.address_` pin. Dropping any one is exploitable.

The two events now come from **different** source contracts — `Deposited` from
the escrow, `Harvested` from the adapter — so the pin is per-event, not one
shared `i_sourceVault`. That is the cost of making Ethereum dumb: custody and
strategy are separate contracts, and each is trusted only for its own event.

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
        return (s_collateral[user] * yieldRateBps) / debt;
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
    mapping(uint256 => uint256) public s_collateral;   // was mapping(address => ...)
    mapping(uint256 => uint256) public s_debt;
    mapping(uint256 => uint256) public s_repaidByYield;
    mapping(uint256 => uint256) public s_marker;

    mapping(address => uint256) public s_positionOf;   // one position per depositor, v1

    function onDeposit(address user, uint256 assets) external onlyASC {
        uint256 id = s_positionOf[user];
        if (id == 0) { id = ++s_nextId; s_positionOf[user] = id; _mint(user, id); }
        _settle(id);
        s_collateral[id] += assets;
        s_totalCollateral += assets;
    }
}
```

**Unresolved:** the score rides on the position, so selling the NFT sells the
repayment record. Either make it soulbound in v1 (`_update` guard, as in step 1)
or accept it and say so. Do not ship it undecided.

Note this is now the *only* transferability question in the system — the escrow
issues nothing, so there is no second one on Ethereum.

---

## 8. `IYieldAdapter`

Extract from `AaveV4Adapter`'s existing surface. Costs nothing, and it is the
concrete thing behind the multi-strategy roadmap claim.

```solidity
interface IYieldAdapter {
    function deposit(uint256 amount) external returns (uint256 assets);
    function withdraw(uint256 amount, address to) external returns (uint256 assets);
    function harvest() external returns (uint256 assets);
    function totalAssets() external view returns (uint256);  // principal + unharvested yield
    function yieldAccrued() external view returns (uint256);
}
```

`RiyaEscrow` holds `IYieldAdapter`, never `AaveV4Adapter` — that indirection is
the entire multi-strategy roadmap claim, and it is the reason the escrow stays a
separate contract instead of folding into the adapter: depositors keep one
address while the strategy behind it is swappable.

`principal()` is gone from the interface. It only ever existed to feed a share
price; the escrow does not compute one. `s_principal` stays internal to the
adapter for `yieldAccrued()`.

Recreate `src/interfaces/IVault.sol` here with the escrow's surface, for the
adapter's `onlyVault` side and for scripts.

---

## Demo sequence this enables

1. Two wallets deposit into `RiyaEscrow` → two `Deposited` events → one proof
   each → collateral credited on Creditcoin.
2. Both borrow at 10%.
3. `AaveV4Adapter.harvest()` → **one** transaction, **one** proof → both debts
   fall pro-rata. *This is the shot: one proof, N borrowers.*
4. Wallet A calls `repay()` → debt clears, score does not move. Shows the two
   paths are different on purpose.
5. Another harvest crosses wallet B's tier → limit jumps → B redraws.

Step 3 is the argument for §3.1 and the only frame in which the mainnet
economics work.

## Test checklist

- Escrow exposes no withdraw path; `AaveV4Adapter.withdraw` reverts for non-vault.
- Deposit below `i_minDeposit` reverts.
- Harvest below `i_minHarvest` reverts.
- `onHarvest` with zero total collateral reverts.
- Fee split: gross 100 → 15 to `s_protocolFees`, 85 distributed.
- Two depositors, one harvest → split exactly pro-rata; no dust loss.
- Pending yield above outstanding debt → surplus lands in `s_credit`.
- Same proof twice → `RiyaASC__AlreadyConsumed`.
- Reverted source tx (`status == 0`) → rejected.
- `Harvested` emitted by an impostor contract → ignored.
- `Deposited` emitted by the adapter, or `Harvested` by the escrow → ignored
  (the per-event address pins are not interchangeable).
- Borrow above limit reverts; borrow at exactly the limit succeeds.
- Borrow/repay loop does not raise the score.
