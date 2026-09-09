// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/// @notice Runs riya's Ethereum leg with no network, against `MockAaveSpoke`.
/// @dev Drives `HelperConfig` rather than deploying the mocks inline, because
///      `getAnvilConfig` returning a usable reserve is half of what is under test.
contract LocalSourceChainTest is Test {
    event TokensHarvested(address indexed caller, uint256 indexed assets);

    HelperConfig helperConfig;
    MockAaveSpoke spoke;
    MockUSD usd;
    AaveV4Adapter adapter;
    RiyaEscrow escrow;

    uint256 reserveId;
    uint256 minHarvest;
    uint256 minDeposit;

    address user = makeAddr("user");
    address keeper = makeAddr("keeper");
    address funder = makeAddr("funder");

    function setUp() public {
        helperConfig = new HelperConfig();

        address spokeAddress;
        (spokeAddress, reserveId, minHarvest, minDeposit) = helperConfig.activeNetworkConfig();

        spoke = MockAaveSpoke(spokeAddress);
        usd = MockUSD(spoke.getReserve(reserveId).underlying);

        uint256 nonce = vm.getNonce(address(this));
        address predictedEscrow = vm.computeCreateAddress(address(this), nonce + 1);

        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(spokeAddress), reserveId, minHarvest);
        escrow = new RiyaEscrow(address(adapter), minDeposit);

        assertEq(address(escrow), predictedEscrow);
    }

    function testAnvilConfigDeploysAUsableReserve() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertTrue(address(spoke) != address(0));
        assertEq(usd.decimals(), 6);
        assertEq(address(adapter.I_ASSET()), address(usd));
        assertEq(minDeposit, 100e6);
        assertEq(minHarvest, 10e6);
    }

    /// @dev The adapter's constructor relies on this revert to make a wrong id undeployable.
    function testUnlistedReserveIsUndeployable() external {
        // ARRANGE
        uint256 badId = reserveId + 99;

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(MockAaveSpoke__ReserveNotListed.selector, badId));
        new AaveV4Adapter(address(escrow), IAaveV4Spoke(address(spoke)), badId, minHarvest);
    }

    function testDepositReachesTheSpokeAsPrincipal() external {
        // ARRANGE
        // ACT
        _deposit(user, minDeposit);

        // ASSERT
        assertEq(adapter.s_principal(), minDeposit);
        assertEq(adapter.totalAssets(), minDeposit);
        assertEq(adapter.yieldAccrued(), 0);
        assertEq(usd.balanceOf(address(adapter)), 0, "adapter must hold no idle balance");
    }

    /// @dev Yield must show up as growth in `getUserSuppliedAssets` and nowhere else,
    ///      because that is the only figure `yieldAccrued` reads.
    function testAccruedYieldIsVisibleAsYieldNotPrincipal() external {
        // ARRANGE
        _deposit(user, minDeposit);

        // ACT
        _accrue(minHarvest);

        // ASSERT
        assertEq(adapter.s_principal(), minDeposit);
        assertEq(adapter.totalAssets(), minDeposit + minHarvest);
        assertEq(adapter.yieldAccrued(), minHarvest);
    }

    function testHarvestBelowFloorReverts() external {
        // ARRANGE
        _deposit(user, minDeposit);
        _accrue(minHarvest - 1);

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                AaveV4Adapter.AaveV4Adapter__HarvestBelowMinimum.selector, minHarvest - 1, minHarvest
            )
        );
        vm.prank(keeper);
        adapter.harvest();
    }

    /// @dev The event the readability worker proves. It fires after the transfer, so its
    ///      presence in a successful transaction means the money moved.
    function testHarvestMovesYieldToTheEscrowAndEmits() external {
        // ARRANGE
        _deposit(user, minDeposit);
        _accrue(minHarvest);

        // ACT
        vm.expectEmit(true, true, false, false, address(adapter));
        emit TokensHarvested(keeper, minHarvest);

        vm.prank(keeper);
        uint256 harvested = adapter.harvest();

        // ASSERT
        assertEq(harvested, minHarvest);
        assertEq(usd.balanceOf(address(escrow)), minHarvest, "yield must arrive before the proof");
        assertEq(adapter.s_principal(), minDeposit, "principal keeps earning");
        assertEq(adapter.yieldAccrued(), 0);
    }

    function testHarvestIsPermissionless() external {
        // ARRANGE
        _deposit(user, minDeposit);
        _accrue(minHarvest);

        // ACT
        vm.prank(makeAddr("stranger"));
        adapter.harvest();

        // ASSERT
        assertEq(usd.balanceOf(address(escrow)), minHarvest);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address from, uint256 amount) internal {
        usd.mint(from, amount);

        vm.startPrank(from);
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

/// @dev File scope so the selector is reachable in `expectRevert`.
error MockAaveSpoke__ReserveNotListed(uint256 reserveId);
