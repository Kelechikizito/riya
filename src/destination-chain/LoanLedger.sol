// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {IRiyaASC} from "src/interfaces/IRiyaASC.sol";

/**
 * @title LoanLedger
 * @author Kelechi Kizito Ugwu
 * @notice Holds every riya position: collateral proven from Ethereum, debt in `RiyaUSD`, and
 *         the repayment record that sets a borrower's limit.
 * @dev Two entry paths that authenticate differently and must never be merged. `onDeposit`
 *      and `onHarvest` are the proof path, reachable only from `RiyaASC`; `borrow` and
 *      `repay` are the user path, bounded by what the proof path already wrote.
 *
 *      Yield uses the MasterChef accumulator, so distribution is O(1) in depositor count.
 *      All amounts are in USDC's 6 decimals; `PRECISION` is the sole exception.
 */
contract LoanLedger is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error LoanLedger__NotASCContract();
    error LoanLedger__ZeroAddress();
    error LoanLedger__ExceedsLimit();

    /// @dev Permanent, not transient. The worker dead-letters it rather than retrying.
    error LoanLedger__NoCollateral();

    error LoanLedger__ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice The only contract allowed on the proof path.
    IRiyaASC public immutable I_RIYA_ASC;

    /// @notice The token this ledger holds sole mint and burn authority over.
    RiyaUSD public immutable I_RIYA_USD;

    /// @dev Scales `s_yieldPerShare` only. A harvest over total collateral is a fraction
    ///      well below one in 6-decimal units, and without this it truncates to zero.
    uint256 private constant PRECISION = 1e18;

    /// @dev Yield worth 20% of collateral earns the top score.
    uint256 private constant GRADUATION_TARGET_BPS = 2_000;

    /// @dev The protocol's cut of each gross harvest.
    uint256 private constant FEE_BPS = 1_500;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Proven Ethereum deposits, one collateral unit per dollar escrowed.
    /// @dev Written only by `onDeposit`, so it is exactly the sum of that user's verified
    ///      `TokensDepositedConfirmedByEscrow` events.
    mapping(address user => uint256 collateralAmount) public s_collateral;

    /// @notice The accumulator's denominator.
    uint256 public s_totalCollateral;

    /// @notice Outstanding RiyaUSD debt.
    /// @dev `repay` burns tokens against it; `_settle` retires it without burning. Only
    ///      the first reduces circulating supply.
    mapping(address user => uint256 debtAmount) public s_debt;

    /// @notice Debt retired by yield. The credit score's entire basis.
    /// @dev Excludes cash repayment, or a borrower could buy the top tier by borrowing and
    ///      repaying the same dollar in a loop.
    mapping(address user => uint256 repaidByYieldAmount) public s_repaidByYield;

    /// @notice Yield that arrived with no debt left to retire.
    /// @dev A v1 record, not a spendable balance: paying it out needs the outbound leg,
    ///      which writability does not yet provide.
    mapping(address user => uint256 creditAmount) public s_credit;

    /// @notice Accumulated protocol fees. A claim on the Ethereum escrow, like `s_credit`.
    uint256 public s_protocolFees;

    /// @notice Yield distributed per unit of collateral, ever, scaled by `PRECISION`.
    uint256 public s_yieldPerShare;

    /// @notice `s_yieldPerShare` at a user's last settlement.
    /// @dev The gap to the current value, times their collateral, is what they are owed.
    mapping(address user => uint256 yieldPerShareMarker) public s_marker;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice A proven Ethereum deposit landed as collateral. Carries the resulting
    ///         balances so a frontend needs no follow-up call.
    event CollateralAdded(address indexed user, uint256 assets, uint256 newCollateral, uint256 newTotal);

    /// @notice A proven harvest was split and distributed.
    /// @dev `newYieldPerShare` lets an indexer derive any user's pending yield from their
    ///      marker alone.
    event YieldDistributed(uint256 gross, uint256 fee, uint256 newYieldPerShare);

    /// @notice Yield was applied to a user's debt during settlement.
    /// @dev `surplus` had no debt left to reduce and became `s_credit`. Only `applied`
    ///      moves the credit score.
    event DebtRetired(address indexed user, uint256 applied, uint256 surplus);

    event Borrowed(address indexed user, uint256 amount);

    /// @dev `amount` is what was burned: the lesser of the request and the debt.
    event Repaid(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Must stay `msg.sender` even if this contract later inherits `ERC2771Context`.
    ///      A forwarder-relative sender would let a relayed call claim to be the ASC.
    modifier onlyASC() {
        if (msg.sender != address(I_RIYA_ASC)) revert LoanLedger__NotASCContract();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @param ascContract The `RiyaASC` that will hold sole access to the proof path.
     * @param riyaUSD The token this ledger mints and burns.
     * @dev Both pins are immutable, so these arguments are the entire trust configuration.
     *      `riyaUSD` is circular with the token's own pin, so the deploy script predicts
     *      this address and asserts the prediction after.
     */
    constructor(address ascContract, RiyaUSD riyaUSD) {
        if (ascContract == address(0)) revert LoanLedger__ZeroAddress();
        if (address(riyaUSD) == address(0)) revert LoanLedger__ZeroAddress();

        I_RIYA_ASC = IRiyaASC(ascContract);
        I_RIYA_USD = riyaUSD;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Credits a proven `RiyaEscrow` deposit as collateral.
     * @param user The Ethereum depositor's address, reused verbatim on Creditcoin.
     * @param assets The amount escrowed, in USDC's 6 decimals.
     * @dev Settles first, without exception: raising collateral before settling would pay
     *      the user for a position they did not hold while the yield accrued. Arguments are
     *      unchecked because the proof is the validation.
     */
    function onDeposit(address user, uint256 assets) external nonReentrant onlyASC {
        _settle(user);
        s_collateral[user] += assets;
        s_totalCollateral += assets;

        emit CollateralAdded(user, assets, s_collateral[user], s_totalCollateral);
    }

    /**
     * @notice Distributes a proven `AaveV4Adapter` harvest across every open position.
     * @param gross The yield that reached the escrow, before the protocol fee.
     * @dev One addition to `s_yieldPerShare`, so a harvest costs the same at any scale.
     *      Reverts on zero collateral rather than returning early, because an early return
     *      would consume the proof and lose the yield with no record of it.
     */
    function onHarvest(uint256 gross) external nonReentrant onlyASC {
        if (s_totalCollateral == 0) revert LoanLedger__NoCollateral();

        uint256 fee = (gross * FEE_BPS) / BPS_DENOMINATOR;
        s_protocolFees += fee;
        s_yieldPerShare += ((gross - fee) * PRECISION) / s_totalCollateral;

        emit YieldDistributed(gross, fee, s_yieldPerShare);
    }

    /**
     * @notice Draws RiyaUSD against proven collateral, up to the caller's current limit.
     * @param amount The amount to borrow, in USDC's 6 decimals.
     * @dev `s_collateral` is by construction the sum of that address's verified Ethereum
     *      deposits, so the LTV check below is the source-chain check. Settles first, so
     *      yield since the last touch has already raised the limit.
     */
    function borrow(uint256 amount) external nonReentrant {
        // CHECKS
        if (amount == 0) revert LoanLedger__ZeroAmount();

        // EFFECTS
        address user = msg.sender;
        _settle(user);

        uint256 limit = (s_collateral[user] * maxLtvBps(user)) / BPS_DENOMINATOR;
        if (s_debt[user] + amount > limit) revert LoanLedger__ExceedsLimit();

        s_debt[user] += amount;

        // INTERACTIONS
        I_RIYA_USD.mint(user, amount);

        emit Borrowed(user, amount);
    }

    /**
     * @notice Repays debt in cash, burning the caller's own RiyaUSD.
     * @param amount The amount to repay. Clamped to outstanding debt rather than reverting.
     * @dev Does not touch `s_repaidByYield`, and that omission is the credit model: counting
     *      cash repayment would let anyone buy the top tier in a borrow/repay loop.
     */
    function repay(uint256 amount) external nonReentrant {
        // CHECKS
        if (amount == 0) revert LoanLedger__ZeroAmount();

        // EFFECTS
        address user = msg.sender;
        _settle(user);

        uint256 debt = s_debt[user];
        uint256 paid = amount < debt ? amount : debt;

        s_debt[user] = debt - paid;

        // INTERACTIONS
        I_RIYA_USD.burn(user, paid);

        emit Repaid(user, paid);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Applies a user's accrued yield to their debt and advances their marker.
     * @param user The position to settle.
     * @dev Must run before any change to collateral or debt. The marker write sits outside
     *      the `collateral != 0` guard on purpose: moving it inside would leave a first-time
     *      depositor's marker at zero and pay them the entire distribution history.
     */
    function _settle(address user) internal {
        uint256 collateral = s_collateral[user];
        uint256 acc = s_yieldPerShare;

        if (collateral != 0) {
            uint256 pending = (collateral * (acc - s_marker[user])) / PRECISION;
            if (pending != 0) {
                uint256 debt = s_debt[user];
                uint256 applied = pending < debt ? pending : debt;

                s_debt[user] = debt - applied;
                s_repaidByYield[user] += applied; // score counts proven dollars only
                s_credit[user] += pending - applied; // surplus when debt is already clear

                emit DebtRetired(user, applied, pending - applied);
            }
        }

        s_marker[user] = acc;
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice How fast a position repays itself at a given yield rate.
     * @param user The position to measure.
     * @param yieldRateBps The source-chain yield rate to assume, in basis points.
     * @return bps Debt retired per period, in basis points of the debt. Zero when no debt.
     * @dev Takes the rate as an argument because the real rate lives on Aave on Ethereum
     *      and this contract cannot read it.
     */
    function selfRepayRateBps(address user, uint256 yieldRateBps) external view returns (uint256 bps) {
        uint256 debt = s_debt[user];
        if (debt == 0) return 0;
        return (s_collateral[user] * yieldRateBps) / debt;
    }

    /**
     * @notice Yield a user has earned but not yet had applied to their debt.
     * @dev Mirrors `_settle` without writing. Stored numbers only move when `_settle` runs,
     *      so between harvests `s_debt` reads stale and this is the difference.
     */
    function pendingYield(address user) public view returns (uint256) {
        uint256 collateral = s_collateral[user];
        if (collateral == 0) return 0;
        return (collateral * (s_yieldPerShare - s_marker[user])) / PRECISION;
    }

    /**
     * @notice A user's credit score, from 0 to 100.
     * @param user The borrower to score.
     * @return The share of the graduation target repaid from yield, capped at 100.
     * @dev Measured against current collateral, so a fresh deposit lowers the score while
     *      raising the absolute borrow limit.
     */
    function score(address user) public view returns (uint256) {
        uint256 target = (s_collateral[user] * GRADUATION_TARGET_BPS) / BPS_DENOMINATOR;
        if (target == 0) return 0;

        uint256 s = (s_repaidByYield[user] * 100) / target;
        return s > 100 ? 100 : s;
    }

    /**
     * @notice The loan-to-value ceiling a user's score currently earns them.
     * @param user The borrower.
     * @return The ceiling in basis points, from 1_000 to 5_000.
     * @dev A ladder, not a curve, so the next rung is a number a user can aim at. The top
     *      rung keeps every position at least 2x over-collateralised.
     */
    function maxLtvBps(address user) public view returns (uint256) {
        uint256 s = score(user);
        if (s < 20) return 1_000;
        if (s < 40) return 2_000;
        if (s < 60) return 3_000;
        if (s < 85) return 4_000;
        return 5_000;
    }
}
