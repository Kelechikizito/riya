// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";

/// @notice Covers riya's accounting: the accumulator, the fee, the score and the LTV ladder.
/// @dev `onlyASC` checks `msg.sender` and nothing else, so a plain address stands in for
///      `RiyaASC` here. What the ASC does before calling is `RiyaASCTest`'s subject.
contract LoanLedgerTest is Test {
    event CollateralAdded(address indexed user, uint256 assets, uint256 newCollateral, uint256 newTotal);
    event YieldDistributed(uint256 gross, uint256 fee, uint256 newYieldPerShare);
    event DebtRetired(address indexed user, uint256 applied, uint256 surplus);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    LoanLedger ledger;
    RiyaUSD riyaUSD;

    address asc = makeAddr("asc");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant PRECISION = 1e18;
    uint256 constant BPS = 10_000;
    uint256 constant FEE_BPS = 1_500;

    function setUp() public {
        uint256 nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 1);

        riyaUSD = new RiyaUSD(predictedLedger);
        ledger = new LoanLedger(asc, riyaUSD);

        assertEq(address(ledger), predictedLedger);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorStoresBothPins() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(address(ledger.I_RIYA_ASC()), asc);
        assertEq(address(ledger.I_RIYA_USD()), address(riyaUSD));
    }

    function testConstructorRejectsZeroAsc() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ZeroAddress.selector);
        new LoanLedger(address(0), riyaUSD);
    }

    function testConstructorRejectsZeroToken() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ZeroAddress.selector);
        new LoanLedger(asc, RiyaUSD(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                               ONDEPOSIT
    //////////////////////////////////////////////////////////////*/

    function testOnDepositCreditsCollateralAndEmits() external {
        // ARRANGE
        // ACT
        vm.expectEmit(true, false, false, true, address(ledger));
        emit CollateralAdded(alice, 1_000e6, 1_000e6, 1_000e6);

        vm.prank(asc);
        ledger.onDeposit(alice, 1_000e6);

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
        assertEq(ledger.s_totalCollateral(), 1_000e6);
    }

    function testOnDepositAccumulatesAcrossUsers() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        _deposit(bob, 3_000e6);

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
        assertEq(ledger.s_collateral(bob), 3_000e6);
        assertEq(ledger.s_totalCollateral(), 4_000e6);
    }

    function testOnDepositRejectsNonAsc() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__NotASCContract.selector);
        vm.prank(alice);
        ledger.onDeposit(alice, 1_000e6);
    }

    /// @dev The ordering rule. Yield that accrued before a second deposit must be valued
    ///      against the old collateral, or a late depositor is paid for a position they
    ///      did not hold.
    function testSecondDepositDoesNotBackdateYield() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);
        _harvest(100e6);

        // ACT
        _deposit(alice, 1_000e6);

        // ASSERT
        // 85 distributed over the 1,000 she held at harvest time, not the 2,000 she holds
        // now. Settling inside `onDeposit` is what pins it to the old balance.
        assertEq(ledger.s_repaidByYield(alice), 85e6);
        assertEq(ledger.pendingYield(alice), 0);
        assertEq(ledger.s_collateral(alice), 2_000e6);

        // The next harvest is valued at the new balance.
        _harvest(100e6);
        assertEq(ledger.pendingYield(alice), 85e6);
    }

    /*//////////////////////////////////////////////////////////////
                               ONHARVEST
    //////////////////////////////////////////////////////////////*/

    function testOnHarvestTakesTheFeeAndDistributesTheRest() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        uint256 gross = 100e6;
        uint256 fee = (gross * FEE_BPS) / BPS;

        // ACT
        vm.expectEmit(false, false, false, true, address(ledger));
        emit YieldDistributed(gross, fee, ((gross - fee) * PRECISION) / 1_000e6);

        vm.prank(asc);
        ledger.onHarvest(gross);

        // ASSERT
        assertEq(ledger.s_protocolFees(), fee);
        assertEq(ledger.s_yieldPerShare(), ((gross - fee) * PRECISION) / 1_000e6);
        assertEq(ledger.pendingYield(alice), gross - fee);
    }

    /// @dev The pro-rata split, and the reason `PRECISION` exists. Alice holds a quarter of
    ///      the collateral, so she takes a quarter of the distributed yield.
    function testOnHarvestSplitsProRata() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _deposit(bob, 3_000e6);

        // ACT
        _harvest(400e6);

        // ASSERT
        uint256 distributed = 400e6 - (400e6 * FEE_BPS) / BPS;
        assertEq(ledger.pendingYield(alice), distributed / 4);
        assertEq(ledger.pendingYield(bob), (distributed * 3) / 4);
    }

    function testOnHarvestRejectsNonAsc() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__NotASCContract.selector);
        vm.prank(alice);
        ledger.onHarvest(100e6);
    }

    /// @dev Permanent, not transient. The worker dead-letters this rather than retrying,
    ///      and softening it into an early return would consume the proof and lose the
    ///      yield with no record.
    function testOnHarvestWithNoCollateralReverts() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__NoCollateral.selector);
        vm.prank(asc);
        ledger.onHarvest(100e6);
    }

    /*//////////////////////////////////////////////////////////////
                                 BORROW
    //////////////////////////////////////////////////////////////*/

    function testBorrowMintsUpToTheLimit() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        vm.expectEmit(true, false, false, true, address(ledger));
        emit Borrowed(alice, 100e6);

        vm.prank(alice);
        ledger.borrow(100e6);

        // ASSERT
        assertEq(ledger.s_debt(alice), 100e6);
        assertEq(riyaUSD.balanceOf(alice), 100e6);
        assertEq(riyaUSD.totalSupply(), 100e6);
    }

    function testBorrowRejectsZero() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ZeroAmount.selector);
        vm.prank(alice);
        ledger.borrow(0);
    }

    function testBorrowBeyondTheLimitReverts() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ExceedsLimit.selector);
        vm.prank(alice);
        ledger.borrow(100e6 + 1);
    }

    /// @dev With no collateral the limit is zero, so any borrow exceeds it. This is the
    ///      source-chain check: `s_collateral` is only ever written from a proven deposit.
    function testBorrowWithoutAProvenDepositReverts() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ExceedsLimit.selector);
        vm.prank(alice);
        ledger.borrow(1);
    }

    /*//////////////////////////////////////////////////////////////
                                 REPAY
    //////////////////////////////////////////////////////////////*/

    function testRepayBurnsAndClearsDebt() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        vm.expectEmit(true, false, false, true, address(ledger));
        emit Repaid(alice, 40e6);

        vm.prank(alice);
        ledger.repay(40e6);

        // ASSERT
        assertEq(ledger.s_debt(alice), 60e6);
        assertEq(riyaUSD.balanceOf(alice), 60e6);
        assertEq(riyaUSD.totalSupply(), 60e6);
    }

    /// @dev Clamped, so a user can clear a position without computing the exact figure.
    function testRepayClampsToOutstandingDebt() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        vm.prank(alice);
        ledger.repay(500e6);

        // ASSERT
        assertEq(ledger.s_debt(alice), 0);
        assertEq(riyaUSD.balanceOf(alice), 0);
    }

    function testRepayRejectsZero() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ZeroAmount.selector);
        vm.prank(alice);
        ledger.repay(0);
    }

    /// @dev The credit model. If cash repayment counted, a borrow/repay loop would buy the
    ///      top tier outright.
    function testRepayDoesNotMoveTheScore() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        vm.prank(alice);
        ledger.repay(100e6);

        // ASSERT
        assertEq(ledger.s_repaidByYield(alice), 0);
        assertEq(ledger.score(alice), 0);
        assertEq(ledger.maxLtvBps(alice), 1_000);
    }

    /*//////////////////////////////////////////////////////////////
                                _SETTLE
    //////////////////////////////////////////////////////////////*/

    function testYieldRetiresDebtAndCountsTowardTheScore() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        _harvest(100e6);

        vm.expectEmit(true, false, false, true, address(ledger));
        emit DebtRetired(alice, 85e6, 0);
        _settle(alice);

        // ASSERT
        assertEq(ledger.s_debt(alice), 15e6);
        assertEq(ledger.s_repaidByYield(alice), 85e6);
        assertEq(ledger.s_credit(alice), 0);
    }

    /// @dev Surplus becomes `s_credit`, never extra `s_repaidByYield`, or the score would
    ///      inflate on yield that retired nothing.
    function testSurplusYieldBecomesCreditNotScore() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 50e6);

        // ACT
        _harvest(100e6);
        _settle(alice);

        // ASSERT
        assertEq(ledger.s_debt(alice), 0);
        assertEq(ledger.s_repaidByYield(alice), 50e6);
        assertEq(ledger.s_credit(alice), 35e6);
    }

    /// @dev The marker advances even with no position, so a first-time depositor is not
    ///      paid the protocol's entire distribution history on their first settlement.
    function testMarkerAdvancesForAUserWithNoCollateral() external {
        // ARRANGE
        _deposit(bob, 1_000e6);
        _harvest(100e6);

        // ACT
        vm.prank(asc);
        ledger.onDeposit(alice, 1_000e6);

        // ASSERT
        assertEq(ledger.s_marker(alice), ledger.s_yieldPerShare());
        assertEq(ledger.pendingYield(alice), 0);
        assertEq(ledger.s_repaidByYield(alice), 0);
    }

    /// @dev A settle with nothing to apply must still be free of side effects.
    function testSettleWithNoPendingYieldChangesNothing() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        _settle(alice);

        // ASSERT
        assertEq(ledger.s_debt(alice), 100e6);
        assertEq(ledger.s_repaidByYield(alice), 0);
        assertEq(ledger.s_credit(alice), 0);
    }

    /// @dev Settlement moves `s_debt` without burning, so supply outruns outstanding debt.
    function testYieldSettlementDoesNotBurnSupply() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        _harvest(100e6);
        _settle(alice);

        // ASSERT
        assertEq(ledger.s_debt(alice), 15e6);
        assertEq(riyaUSD.totalSupply(), 100e6);
        assertEq(riyaUSD.balanceOf(alice), 100e6);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEWS AND LADDER
    //////////////////////////////////////////////////////////////*/

    function testPendingYieldIsZeroWithoutCollateral() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(ledger.pendingYield(alice), 0);
    }

    function testScoreIsZeroWithoutCollateral() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(ledger.score(alice), 0);
        assertEq(ledger.maxLtvBps(alice), 1_000);
    }

    function testScoreCapsAtOneHundred() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _climbToTopRung(alice);

        // ACT
        _retireByYield(alice, 200e6);

        // ASSERT
        assertEq(ledger.s_repaidByYield(alice), 400e6, "double the graduation target");
        assertEq(ledger.score(alice), 100);
    }

    /// @dev Every rung of the ladder, walked from the bottom.
    function testLtvLadderClimbsWithTheScore() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        // ASSERT
        // Each step borrows only what the current rung allows, which is why the ladder has
        // to be climbed rather than jumped.
        assertEq(ledger.maxLtvBps(alice), 1_000);

        _retireByYield(alice, 50e6);
        assertEq(ledger.score(alice), 25);
        assertEq(ledger.maxLtvBps(alice), 2_000);

        _retireByYield(alice, 50e6);
        assertEq(ledger.score(alice), 50);
        assertEq(ledger.maxLtvBps(alice), 3_000);

        _retireByYield(alice, 30e6);
        assertEq(ledger.score(alice), 65);
        assertEq(ledger.maxLtvBps(alice), 4_000);

        _retireByYield(alice, 70e6);
        assertEq(ledger.score(alice), 100);
        assertEq(ledger.maxLtvBps(alice), 5_000);
    }

    /// @dev A raised limit is real: at the top rung Alice may draw half her collateral.
    function testGraduatedBorrowerCanDrawTheHigherLimit() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _climbToTopRung(alice);

        // ACT
        vm.prank(alice);
        ledger.borrow(500e6);

        // ASSERT
        assertEq(ledger.s_debt(alice), 500e6);
        assertEq(ledger.maxLtvBps(alice), 5_000);
    }

    function testSelfRepayRateIsZeroWithoutDebt() external {
        // ARRANGE
        _deposit(alice, 1_000e6);

        // ACT
        // ASSERT
        assertEq(ledger.selfRepayRateBps(alice, 500), 0);
    }

    /// @dev 5% on 1,000 of collateral is 50 a year against 100 of debt, so the yield covers
    ///      half the loan per period: 5_000 bps.
    function testSelfRepayRateScalesWithCollateralOverDebt() external {
        // ARRANGE
        _deposit(alice, 1_000e6);
        _borrow(alice, 100e6);

        // ACT
        // ASSERT
        assertEq(ledger.selfRepayRateBps(alice, 500), 5_000);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address user, uint256 amount) internal {
        vm.prank(asc);
        ledger.onDeposit(user, amount);
    }

    function _harvest(uint256 gross) internal {
        vm.prank(asc);
        ledger.onHarvest(gross);
    }

    function _borrow(address user, uint256 amount) internal {
        vm.prank(user);
        ledger.borrow(amount);
    }

    /// @dev Settles without moving the position. `onDeposit` is the only route to `_settle`
    ///      that neither mints nor burns, and zero assets leave collateral untouched.
    function _settle(address user) internal {
        vm.prank(asc);
        ledger.onDeposit(user, 0);
    }

    /// @dev Borrows `amount` and harvests enough yield to retire exactly that, which is the
    ///      only thing that moves the score. 85% of gross is distributed, so gross is
    ///      grossed up by the fee.
    function _retireByYield(address user, uint256 amount) internal {
        _borrow(user, amount);

        uint256 gross = (amount * BPS) / (BPS - FEE_BPS);
        _harvest(gross);
        _settle(user);
    }

    /// @dev Walks the ladder from 1_000 to 5_000 bps on 1,000 of collateral, borrowing only
    ///      what each rung allows. Ends at exactly the graduation target.
    function _climbToTopRung(address user) internal {
        _retireByYield(user, 50e6);
        _retireByYield(user, 50e6);
        _retireByYield(user, 30e6);
        _retireByYield(user, 70e6);
    }
}
