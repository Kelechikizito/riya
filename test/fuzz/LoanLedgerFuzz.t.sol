// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";

/**
 * @title LoanLedgerFuzz
 * @author Kelechi Kizito Ugwu
 * @notice Stateless fuzz over riya's accounting: the fee split, the accumulator, the borrow
 *         limit, and the score.
 * @dev Each test builds its own state from the fuzzed inputs and asserts a property that
 *      must hold for every one of them. The unit tests pin chosen numbers; these pin the
 *      relationships between numbers, which is where an accumulator goes wrong.
 *
 *      Amounts are bounded to 1e18 in USDC's 6 decimals, a trillion dollars. Above that
 *      `(gross - fee) * PRECISION` starts crowding 2^256, and the overflow that follows is
 *      an artefact of the fuzzer rather than a reachable state.
 */
contract LoanLedgerFuzz is Test {
    LoanLedger ledger;
    RiyaUSD riyaUSD;

    address asc = makeAddr("asc");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant PRECISION = 1e18;
    uint256 constant BPS = 10_000;
    uint256 constant FEE_BPS = 1_500;

    uint256 constant MIN_AMOUNT = 1e6;
    uint256 constant MAX_AMOUNT = 1e18;

    function setUp() public {
        uint256 nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 1);

        riyaUSD = new RiyaUSD(predictedLedger);
        ledger = new LoanLedger(asc, riyaUSD);
    }

    /*//////////////////////////////////////////////////////////////
                               THE FEE
    //////////////////////////////////////////////////////////////*/

    /// @dev The protocol takes exactly 15% and distributes exactly the rest. Nothing is
    ///      created and nothing is lost between the two.
    function testFuzzFeeAndDistributionSumToGross(uint256 collateral, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);
        _deposit(alice, collateral);

        // ACT
        _harvest(gross);

        // ASSERT
        uint256 fee = ledger.s_protocolFees();
        uint256 distributed = (ledger.s_yieldPerShare() * collateral) / PRECISION;

        assertEq(fee, (gross * FEE_BPS) / BPS);
        assertLe(fee + distributed, gross, "never more than arrived");
        assertLe(gross - (fee + distributed), 1, "and at most one unit of rounding is lost");
    }

    /// @dev A sole depositor's pending yield is the whole distribution, give or take the
    ///      truncation in `s_yieldPerShare`.
    function testFuzzSoleDepositorTakesTheWholeDistribution(uint256 collateral, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);
        _deposit(alice, collateral);

        // ACT
        _harvest(gross);

        // ASSERT
        uint256 distributed = gross - (gross * FEE_BPS) / BPS;
        uint256 pending = ledger.pendingYield(alice);

        assertLe(pending, distributed, "rounding only ever loses");
        assertLe(distributed - pending, 1);
    }

    /// @dev Two positions share one harvest in proportion to collateral, and their shares
    ///      never add up to more than was distributed.
    function testFuzzProRataSplitNeverOverPays(uint256 aliceStake, uint256 bobStake, uint256 gross) external {
        // ARRANGE
        aliceStake = bound(aliceStake, MIN_AMOUNT, MAX_AMOUNT / 2);
        bobStake = bound(bobStake, MIN_AMOUNT, MAX_AMOUNT / 2);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, aliceStake);
        _deposit(bob, bobStake);

        // ACT
        _harvest(gross);

        // ASSERT
        uint256 distributed = gross - (gross * FEE_BPS) / BPS;
        uint256 paid = ledger.pendingYield(alice) + ledger.pendingYield(bob);

        assertLe(paid, distributed, "the accumulator cannot mint yield");

        // The larger stake never takes less than the smaller one.
        if (aliceStake >= bobStake) assertGe(ledger.pendingYield(alice), ledger.pendingYield(bob));
    }

    /*//////////////////////////////////////////////////////////////
                             THE BORROW LIMIT
    //////////////////////////////////////////////////////////////*/

    /// @dev The limit is the whole of the source-chain check. A borrow succeeds if and only
    ///      if it stays inside it, whatever the numbers.
    function testFuzzBorrowSucceedsExactlyWithinTheLimit(uint256 collateral, uint256 amount) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        amount = bound(amount, 1, MAX_AMOUNT);
        _deposit(alice, collateral);

        uint256 limit = (collateral * ledger.maxLtvBps(alice)) / BPS;

        // ACT
        // ASSERT
        if (amount > limit) {
            vm.expectRevert(LoanLedger.LoanLedger__ExceedsLimit.selector);
            vm.prank(alice);
            ledger.borrow(amount);
        } else {
            vm.prank(alice);
            ledger.borrow(amount);

            assertEq(ledger.s_debt(alice), amount);
            assertEq(riyaUSD.balanceOf(alice), amount);
        }
    }

    /// @dev At the bottom rung a position is over-collateralised ten times, and the ladder
    ///      never lets that fall below two.
    function testFuzzDebtNeverExceedsHalfOfCollateral(uint256 collateral, uint256 amount) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        amount = bound(amount, 1, collateral);
        _deposit(alice, collateral);

        // ACT
        vm.prank(alice);
        try ledger.borrow(amount) {}
        catch {
            return;
        }

        // ASSERT
        assertLe(ledger.s_debt(alice) * 2, collateral, "at least 2x over-collateralised");
    }

    /*//////////////////////////////////////////////////////////////
                                 REPAY
    //////////////////////////////////////////////////////////////*/

    /// @dev `repay` clamps rather than reverting, burns exactly what it credits, and never
    ///      touches the score.
    function testFuzzRepayClampsAndBurnsWhatItCredits(uint256 collateral, uint256 borrowed, uint256 repaid) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        repaid = bound(repaid, 1, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(borrowed);

        // ACT
        vm.prank(alice);
        ledger.repay(repaid);

        // ASSERT
        uint256 expectedPaid = repaid < borrowed ? repaid : borrowed;

        assertEq(ledger.s_debt(alice), borrowed - expectedPaid, "clamped, never underflowed");
        assertEq(riyaUSD.balanceOf(alice), borrowed - expectedPaid, "burn matches the credit");
        assertEq(ledger.s_repaidByYield(alice), 0, "cash repayment never buys score");
    }

    /*//////////////////////////////////////////////////////////////
                              SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Every unit of pending yield lands somewhere: against debt, or into credit.
    ///      None of it evaporates and none of it is counted twice.
    function testFuzzSettlementConservesPendingYield(uint256 collateral, uint256 borrowed, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(borrowed);

        _harvest(gross);
        uint256 pending = ledger.pendingYield(alice);

        // ACT
        _settle(alice);

        // ASSERT
        uint256 applied = ledger.s_repaidByYield(alice);
        uint256 surplus = ledger.s_credit(alice);

        assertEq(applied + surplus, pending, "nothing created, nothing lost");
        assertEq(ledger.s_debt(alice), borrowed - applied);
        assertLe(applied, borrowed, "yield cannot retire more debt than exists");
        assertEq(ledger.pendingYield(alice), 0, "the marker caught up");
    }

    /// @dev Settling twice with no harvest in between must be a no-op. If it were not, any
    ///      user could drain the protocol by repeatedly touching their own position.
    function testFuzzSettlingTwiceChangesNothing(uint256 collateral, uint256 borrowed, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(borrowed);
        _harvest(gross);
        _settle(alice);

        uint256 debt = ledger.s_debt(alice);
        uint256 applied = ledger.s_repaidByYield(alice);
        uint256 credit = ledger.s_credit(alice);

        // ACT
        _settle(alice);

        // ASSERT
        assertEq(ledger.s_debt(alice), debt);
        assertEq(ledger.s_repaidByYield(alice), applied);
        assertEq(ledger.s_credit(alice), credit);
    }

    /// @dev Yield retires debt without burning, so supply is never reduced by settlement.
    function testFuzzSettlementNeverBurnsSupply(uint256 collateral, uint256 borrowed, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(borrowed);
        _harvest(gross);

        // ACT
        _settle(alice);

        // ASSERT
        assertEq(riyaUSD.totalSupply(), borrowed, "supply outruns outstanding debt");
        assertGe(riyaUSD.totalSupply(), ledger.s_debt(alice));
    }

    /*//////////////////////////////////////////////////////////////
                            SCORE AND LADDER
    //////////////////////////////////////////////////////////////*/

    /// @dev The score is a percentage, so it must stay inside 0 to 100 whatever state the
    ///      position is in, and the ladder must return one of its five rungs.
    function testFuzzScoreAndLadderStayInBounds(uint256 collateral, uint256 borrowed, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(borrowed);
        _harvest(gross);
        _settle(alice);

        // ACT
        uint256 score = ledger.score(alice);
        uint256 ltv = ledger.maxLtvBps(alice);

        // ASSERT
        assertLe(score, 100);
        assertGe(ltv, 1_000);
        assertLe(ltv, 5_000, "the top rung keeps every position 2x collateralised");
        assertTrue(ltv % 1_000 == 0 && ltv / 1_000 >= 1 && ltv / 1_000 <= 5);
    }

    /// @dev A deposit can only ever lower the score, because the graduation target scales
    ///      with collateral. It must never raise it, or a whale could buy the top rung.
    function testFuzzADepositNeverRaisesTheScore(uint256 collateral, uint256 extra, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT / 2);
        extra = bound(extra, MIN_AMOUNT, MAX_AMOUNT / 2);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        vm.prank(alice);
        ledger.borrow(collateral / 10);
        _harvest(gross);
        _settle(alice);

        uint256 scoreBefore = ledger.score(alice);

        // ACT
        _deposit(alice, extra);

        // ASSERT
        assertLe(ledger.score(alice), scoreBefore);
    }

    /*//////////////////////////////////////////////////////////////
                             TOTALS AND VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @dev The accumulator's denominator must always equal the sum of its numerators, or
    ///      every share is wrong.
    function testFuzzTotalCollateralEqualsTheSumOfPositions(uint256 aliceStake, uint256 bobStake) external {
        // ARRANGE
        aliceStake = bound(aliceStake, MIN_AMOUNT, MAX_AMOUNT / 2);
        bobStake = bound(bobStake, MIN_AMOUNT, MAX_AMOUNT / 2);

        // ACT
        _deposit(alice, aliceStake);
        _deposit(bob, bobStake);

        // ASSERT
        assertEq(ledger.s_totalCollateral(), ledger.s_collateral(alice) + ledger.s_collateral(bob));
    }

    /// @dev `pendingYield` is what the frontend renders between harvests, so it has to agree
    ///      with what settlement actually applies.
    function testFuzzPendingYieldMatchesWhatSettlementApplies(uint256 collateral, uint256 gross) external {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        gross = bound(gross, MIN_AMOUNT, MAX_AMOUNT);

        _deposit(alice, collateral);
        _harvest(gross);

        uint256 predicted = ledger.pendingYield(alice);

        // ACT
        _settle(alice);

        // ASSERT
        // No debt, so the whole pending amount becomes credit.
        assertEq(ledger.s_credit(alice), predicted);
    }

    /// @dev The self-repay rate is collateral over debt at the given yield, and it is zero
    ///      exactly when there is no debt.
    function testFuzzSelfRepayRateIsZeroOnlyWithoutDebt(uint256 collateral, uint256 borrowed, uint256 rateBps)
        external
    {
        // ARRANGE
        collateral = bound(collateral, MIN_AMOUNT, MAX_AMOUNT);
        borrowed = bound(borrowed, 1, collateral / 10);
        rateBps = bound(rateBps, 1, BPS);

        _deposit(alice, collateral);

        // ACT
        // ASSERT
        assertEq(ledger.selfRepayRateBps(alice, rateBps), 0, "no debt, no rate");

        vm.prank(alice);
        ledger.borrow(borrowed);

        assertEq(ledger.selfRepayRateBps(alice, rateBps), (collateral * rateBps) / borrowed);
    }

    /*//////////////////////////////////////////////////////////////
                                 GUARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev The proof path is the only route to collateral, so it must reject every caller
    ///      that is not the ASC, whoever they are.
    function testFuzzOnlyTheAscMayWriteTheProofPath(address caller, uint256 amount) external {
        // ARRANGE
        vm.assume(caller != asc);
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        _deposit(alice, MIN_AMOUNT);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__NotASCContract.selector);
        vm.prank(caller);
        ledger.onDeposit(alice, amount);

        vm.expectRevert(LoanLedger.LoanLedger__NotASCContract.selector);
        vm.prank(caller);
        ledger.onHarvest(amount);
    }

    /// @dev Without a proven deposit the limit is zero, so no borrow of any size succeeds.
    function testFuzzBorrowingWithoutCollateralAlwaysReverts(address user, uint256 amount) external {
        // ARRANGE
        amount = bound(amount, 1, MAX_AMOUNT);

        // ACT
        // ASSERT
        vm.expectRevert(LoanLedger.LoanLedger__ExceedsLimit.selector);
        vm.prank(user);
        ledger.borrow(amount);
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

    /// @dev Settles without moving the position: `onDeposit` of zero assets.
    function _settle(address user) internal {
        vm.prank(asc);
        ledger.onDeposit(user, 0);
    }
}
