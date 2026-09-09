// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/// @notice Covers the adapter's guards and its withdraw path.
/// @dev The happy paths run in `LocalSourceChainTest` through the real escrow. Here the
///      escrow is a plain address, so `onlyEscrow` can be driven directly.
contract AaveV4AdapterTest is Test {
    event TokensWithdrawn(address indexed to, uint256 indexed assets, uint256 indexed shares);

    MockAaveSpoke spoke;
    MockUSD usd;
    AaveV4Adapter adapter;

    address escrow = makeAddr("escrow");
    address funder = makeAddr("funder");
    uint256 reserveId;

    uint256 constant MIN_HARVEST = 10e6;

    function setUp() public {
        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        adapter = new AaveV4Adapter(escrow, IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorStoresEveryPin() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(adapter.I_ESCROW(), escrow);
        assertEq(address(adapter.I_SPOKE()), address(spoke));
        assertEq(adapter.I_RESERVE_ID(), reserveId);
        assertEq(adapter.I_MIN_HARVEST(), MIN_HARVEST);
        assertEq(address(adapter.I_ASSET()), address(usd));
        assertEq(adapter.asset(), address(usd));
    }

    function testConstructorRejectsZeroEscrow() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__ZeroAddress.selector);
        new AaveV4Adapter(address(0), IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
    }

    function testConstructorRejectsZeroSpoke() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__ZeroAddress.selector);
        new AaveV4Adapter(escrow, IAaveV4Spoke(address(0)), reserveId, MIN_HARVEST);
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function testOnlyEscrowMayDeposit() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__NotEscrow.selector);
        vm.prank(makeAddr("stranger"));
        adapter.deposit(100e6);
    }

    function testDepositRejectsZero() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__ZeroAmount.selector);
        vm.prank(escrow);
        adapter.deposit(0);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function testWithdrawReturnsPrincipalAndReducesIt() external {
        // ARRANGE
        _deposit(1_000e6);

        // ACT
        vm.expectEmit(true, true, true, false, address(adapter));
        emit TokensWithdrawn(escrow, 400e6, 400e6);

        vm.prank(escrow);
        uint256 assets = adapter.withdraw(400e6, escrow);

        // ASSERT
        assertEq(assets, 400e6);
        assertEq(adapter.s_principal(), 600e6);
        assertEq(usd.balanceOf(escrow), 400e6);
    }

    /// @dev A full exit takes the yield with it, so principal must floor at zero rather
    ///      than underflow.
    function testFullExitTakesYieldAndFloorsPrincipalAtZero() external {
        // ARRANGE
        _deposit(1_000e6);
        _accrue(100e6);

        // ACT
        vm.prank(escrow);
        uint256 assets = adapter.withdraw(type(uint256).max, escrow);

        // ASSERT
        assertEq(assets, 1_100e6, "principal plus yield");
        assertEq(adapter.s_principal(), 0);
        assertEq(adapter.totalAssets(), 0);
    }

    function testOnlyEscrowMayWithdraw() external {
        // ARRANGE
        _deposit(1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__NotEscrow.selector);
        vm.prank(makeAddr("stranger"));
        adapter.withdraw(100e6, escrow);
    }

    function testWithdrawRejectsZeroAmount() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__ZeroAmount.selector);
        vm.prank(escrow);
        adapter.withdraw(0, escrow);
    }

    function testWithdrawRejectsZeroRecipient() external {
        // ARRANGE
        _deposit(1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(AaveV4Adapter.AaveV4Adapter__ZeroAddress.selector);
        vm.prank(escrow);
        adapter.withdraw(100e6, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                              YIELDACCRUED
    //////////////////////////////////////////////////////////////*/

    /// @dev A reserve carrying a deficit reports less than principal, and that is not a
    ///      negative harvest. Clamping at zero is what keeps `harvest` from underflowing.
    function testYieldAccruedClampsAtZeroOnADeficit() external {
        // ARRANGE
        _deposit(1_000e6);

        // ACT
        spoke.simulateDeficit(reserveId, address(adapter), 200e6);

        // ASSERT
        assertEq(adapter.totalAssets(), 800e6);
        assertEq(adapter.s_principal(), 1_000e6);
        assertEq(adapter.yieldAccrued(), 0);
    }

    function testHarvestOnADeficitRevertsBelowTheFloor() external {
        // ARRANGE
        _deposit(1_000e6);
        spoke.simulateDeficit(reserveId, address(adapter), 200e6);

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(AaveV4Adapter.AaveV4Adapter__HarvestBelowMinimum.selector, 0, MIN_HARVEST)
        );
        adapter.harvest();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal {
        usd.mint(escrow, amount);

        vm.prank(escrow);
        usd.approve(address(adapter), amount);

        vm.prank(escrow);
        adapter.deposit(amount);
    }

    function _accrue(uint256 amount) internal {
        usd.mint(funder, amount);

        vm.startPrank(funder);
        usd.approve(address(spoke), amount);
        spoke.accrueYield(reserveId, address(adapter), amount);
        vm.stopPrank();
    }
}
