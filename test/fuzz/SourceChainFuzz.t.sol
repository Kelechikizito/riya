// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/**
 * @title SourceChainFuzz
 * @author Kelechi Kizito Ugwu
 * @notice Stateless fuzz over the Ethereum leg and the mint lock.
 * @dev The property that matters most here is the principal-versus-yield split. `harvest`
 *      skims everything Aave holds above `s_principal`, so if that line ever drifts the
 *      adapter starts sending users' principal to the escrow and calling it yield.
 */
contract SourceChainFuzz is Test {
    MockAaveSpoke spoke;
    MockUSD usd;
    AaveV4Adapter adapter;
    RiyaEscrow escrow;
    RiyaUSD riyaUSD;

    address user = makeAddr("user");
    address funder = makeAddr("funder");
    address ledger = makeAddr("ledger");
    uint256 reserveId;

    uint256 constant MIN_HARVEST = 10e6;
    uint256 constant MIN_DEPOSIT = 100e6;
    uint256 constant MAX_AMOUNT = 1e24;

    function setUp() public {
        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        uint256 nonce = vm.getNonce(address(this));
        address predictedEscrow = vm.computeCreateAddress(address(this), nonce + 1);

        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
        escrow = new RiyaEscrow(address(adapter), MIN_DEPOSIT);

        riyaUSD = new RiyaUSD(ledger);
    }

    /*//////////////////////////////////////////////////////////////
                                ESCROW
    //////////////////////////////////////////////////////////////*/

    /// @dev The floor guards the worker's CTC, since every deposit costs the same to prove
    ///      whatever its size. It must hold at every amount, not just the ones chosen.
    function testFuzzDepositFloorHoldsAtEveryAmount(uint256 amount) external {
        // ARRANGE
        amount = bound(amount, 1, MAX_AMOUNT);
        usd.mint(user, amount);

        vm.prank(user);
        usd.approve(address(escrow), amount);

        // ACT
        // ASSERT
        if (amount < MIN_DEPOSIT) {
            vm.expectRevert(
                abi.encodeWithSelector(RiyaEscrow.RiyaEscrow__BelowMinDeposit.selector, amount, MIN_DEPOSIT)
            );
            vm.prank(user);
            escrow.deposit(amount);
        } else {
            vm.prank(user);
            escrow.deposit(amount);

            assertEq(adapter.s_principal(), amount);
        }
    }

    /// @dev The escrow forwards in the same transaction, so it never holds a deposit. Any
    ///      balance it does hold is harvested yield waiting for its proof.
    function testFuzzEscrowNeverHoldsADeposit(uint256 amount) external {
        // ARRANGE
        amount = bound(amount, MIN_DEPOSIT, MAX_AMOUNT);

        // ACT
        _deposit(amount);

        // ASSERT
        assertEq(usd.balanceOf(address(escrow)), 0);
        assertEq(usd.balanceOf(address(adapter)), 0, "the adapter holds no idle balance either");
        assertEq(adapter.totalAssets(), amount, "it is all in Aave");
    }

    /*//////////////////////////////////////////////////////////////
                          PRINCIPAL AND YIELD
    //////////////////////////////////////////////////////////////*/

    /// @dev Everything above principal is yield and nothing below it is. Get this wrong and
    ///      `harvest` starts paying out principal.
    function testFuzzYieldIsExactlyWhatSitsAbovePrincipal(uint256 deposited, uint256 accrued) external {
        // ARRANGE
        deposited = bound(deposited, MIN_DEPOSIT, MAX_AMOUNT);
        accrued = bound(accrued, 1, MAX_AMOUNT);
        _deposit(deposited);

        // ACT
        _accrue(accrued);

        // ASSERT
        assertEq(adapter.s_principal(), deposited, "principal never moves on accrual");
        assertEq(adapter.totalAssets(), deposited + accrued);
        assertEq(adapter.yieldAccrued(), accrued);
    }

    /// @dev A reserve carrying a deficit reports less than principal, and that is not a
    ///      negative harvest. Without the clamp the subtraction underflows.
    function testFuzzYieldClampsAtZeroOnAnyDeficit(uint256 deposited, uint256 deficit) external {
        // ARRANGE
        deposited = bound(deposited, MIN_DEPOSIT, MAX_AMOUNT);
        deficit = bound(deficit, 1, deposited);
        _deposit(deposited);

        // ACT
        spoke.simulateDeficit(reserveId, address(adapter), deficit);

        // ASSERT
        assertEq(adapter.yieldAccrued(), 0);
        assertLe(adapter.totalAssets(), adapter.s_principal());
    }

    /// @dev The floor is what stops the keeper burning Ethereum gas on dust, so it has to
    ///      bind at every amount below it and never above.
    function testFuzzHarvestFloorHoldsAtEveryAmount(uint256 deposited, uint256 accrued) external {
        // ARRANGE
        deposited = bound(deposited, MIN_DEPOSIT, MAX_AMOUNT);
        accrued = bound(accrued, 1, MAX_AMOUNT);
        _deposit(deposited);
        _accrue(accrued);

        // ACT
        // ASSERT
        if (accrued < MIN_HARVEST) {
            vm.expectRevert(
                abi.encodeWithSelector(AaveV4Adapter.AaveV4Adapter__HarvestBelowMinimum.selector, accrued, MIN_HARVEST)
            );
            adapter.harvest();
        } else {
            uint256 harvested = adapter.harvest();

            assertEq(harvested, accrued);
            assertEq(usd.balanceOf(address(escrow)), accrued, "the money arrives before the proof");
            assertEq(adapter.s_principal(), deposited, "principal keeps earning");
            assertEq(adapter.yieldAccrued(), 0);
        }
    }

    /// @dev A partial withdrawal takes principal only, and the figure must track exactly, or
    ///      the next `yieldAccrued` is wrong for the rest of the position's life.
    function testFuzzPartialWithdrawTracksPrincipal(uint256 deposited, uint256 taken) external {
        // ARRANGE
        deposited = bound(deposited, MIN_DEPOSIT, MAX_AMOUNT);
        taken = bound(taken, 1, deposited);
        _deposit(deposited);

        // ACT
        vm.prank(address(escrow));
        uint256 assets = adapter.withdraw(taken, address(escrow));

        // ASSERT
        assertEq(assets, taken);
        assertEq(adapter.s_principal(), deposited - taken);
        assertEq(adapter.totalAssets(), deposited - taken);
        assertEq(usd.balanceOf(address(escrow)), taken);
    }

    /// @dev A full exit takes the yield with it, so principal must floor at zero rather than
    ///      underflow, whatever the yield happened to be.
    function testFuzzFullExitFloorsPrincipalAtZero(uint256 deposited, uint256 accrued) external {
        // ARRANGE
        deposited = bound(deposited, MIN_DEPOSIT, MAX_AMOUNT);
        accrued = bound(accrued, 1, MAX_AMOUNT);
        _deposit(deposited);
        _accrue(accrued);

        // ACT
        vm.prank(address(escrow));
        uint256 assets = adapter.withdraw(type(uint256).max, address(escrow));

        // ASSERT
        assertEq(assets, deposited + accrued, "principal plus yield");
        assertEq(adapter.s_principal(), 0);
        assertEq(adapter.totalAssets(), 0);
    }

    /// @dev Only the escrow may move principal, whoever else asks.
    function testFuzzOnlyTheEscrowMayMovePrincipal(address caller, uint256 amount) external {
        // ARRANGE
        vm.assume(caller != address(escrow));
        amount = bound(amount, 1, MAX_AMOUNT);
        _deposit(MIN_DEPOSIT);

        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__NotEscrow.selector);
        vm.prank(caller);
        adapter.deposit(amount);

        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__NotEscrow.selector);
        vm.prank(caller);
        adapter.withdraw(amount, caller);
    }

    /// @dev Anyone may pay the gas to retire someone else's debt, and the yield can still
    ///      only ever go to the escrow.
    function testFuzzHarvestIsPermissionlessButTheDestinationIsFixed(address caller, uint256 accrued) external {
        // ARRANGE
        accrued = bound(accrued, MIN_HARVEST, MAX_AMOUNT);
        vm.assume(caller != address(escrow) && caller != address(spoke) && caller != address(adapter));
        _deposit(MIN_DEPOSIT);
        _accrue(accrued);

        // ACT
        vm.prank(caller);
        adapter.harvest();

        // ASSERT
        assertEq(usd.balanceOf(address(escrow)), accrued);
        assertEq(usd.balanceOf(caller), 0, "the caller gets nothing but the gas bill");
    }

    /*//////////////////////////////////////////////////////////////
                              THE MINT LOCK
    //////////////////////////////////////////////////////////////*/

    /// @dev RiyaUSD cannot come into existence except through the ledger, whoever asks and
    ///      whatever amount they ask for.
    function testFuzzOnlyTheLedgerCanMintOrBurn(address caller, uint256 amount) external {
        // ARRANGE
        vm.assume(caller != ledger);
        amount = bound(amount, 1, MAX_AMOUNT);

        vm.prank(ledger);
        riyaUSD.mint(user, amount);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaUSD.RiyaUSD__NotLedger.selector);
        vm.prank(caller);
        riyaUSD.mint(caller, amount);

        vm.expectRevert(RiyaUSD.RiyaUSD__NotLedger.selector);
        vm.prank(caller);
        riyaUSD.burn(user, amount);

        assertEq(riyaUSD.totalSupply(), amount, "unchanged");
    }

    /// @dev Supply tracks mints minus burns exactly, with no fee and no rebase in between.
    function testFuzzSupplyTracksMintsMinusBurns(uint256 minted, uint256 burned) external {
        // ARRANGE
        minted = bound(minted, 1, MAX_AMOUNT);
        burned = bound(burned, 1, minted);

        // ACT
        vm.startPrank(ledger);
        riyaUSD.mint(user, minted);
        riyaUSD.burn(user, burned);
        vm.stopPrank();

        // ASSERT
        assertEq(riyaUSD.totalSupply(), minted - burned);
        assertEq(riyaUSD.balanceOf(user), minted - burned);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal {
        usd.mint(user, amount);

        vm.startPrank(user);
        usd.approve(address(escrow), amount);
        escrow.deposit(amount);
        vm.stopPrank();
    }

    function _accrue(uint256 amount) internal {
        usd.mint(funder, amount);

        vm.startPrank(funder);
        usd.approve(address(spoke), amount);
        spoke.accrueYield(reserveId, address(adapter), amount);
        vm.stopPrank();
    }
}
