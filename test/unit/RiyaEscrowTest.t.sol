// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";

/// @notice Covers the escrow's guards and the figure it puts in the event the ASC proves.
contract RiyaEscrowTest is Test {
    event TokensDepositedConfirmedByEscrow(address indexed user, uint256 indexed assets);

    MockAaveSpoke spoke;
    MockUSD usd;
    AaveV4Adapter adapter;
    RiyaEscrow escrow;

    address user = makeAddr("user");
    uint256 reserveId;

    uint256 constant MIN_HARVEST = 10e6;
    uint256 constant MIN_DEPOSIT = 100e6;

    function setUp() public {
        usd = new MockUSD();
        spoke = new MockAaveSpoke();
        reserveId = spoke.listReserve(address(usd));

        uint256 nonce = vm.getNonce(address(this));
        address predictedEscrow = vm.computeCreateAddress(address(this), nonce + 1);

        adapter = new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(address(spoke)), reserveId, MIN_HARVEST);
        escrow = new RiyaEscrow(address(adapter), MIN_DEPOSIT);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @dev The asset comes from the adapter, so there is no second copy to disagree.
    function testConstructorDerivesTheAssetFromTheAdapter() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(address(escrow.I_ASSET()), address(usd));
        assertEq(address(escrow.I_ADAPTER()), address(adapter));
        assertEq(escrow.I_MIN_DEPOSIT(), MIN_DEPOSIT);
    }

    function testConstructorRejectsZeroAdapter() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaEscrow.RiyaEscrow__ZeroAddress.selector);
        new RiyaEscrow(address(0), MIN_DEPOSIT);
    }

    function testConstructorRejectsZeroMinDeposit() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaEscrow.RiyaEscrow__ZeroAmount.selector);
        new RiyaEscrow(address(adapter), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @dev The event carries what Aave confirmed, not what the user asked for, because
    ///      that figure becomes their collateral on Creditcoin.
    function testDepositEmitsTheConfirmedAmount() external {
        // ARRANGE
        usd.mint(user, MIN_DEPOSIT);

        vm.prank(user);
        usd.approve(address(escrow), MIN_DEPOSIT);

        // ACT
        vm.expectEmit(true, true, false, false, address(escrow));
        emit TokensDepositedConfirmedByEscrow(user, MIN_DEPOSIT);

        vm.prank(user);
        escrow.deposit(MIN_DEPOSIT);

        // ASSERT
        assertEq(usd.balanceOf(address(escrow)), 0, "forwards everything");
        assertEq(adapter.s_principal(), MIN_DEPOSIT);
    }

    function testDepositRejectsZero() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaEscrow.RiyaEscrow__ZeroAmount.selector);
        vm.prank(user);
        escrow.deposit(0);
    }

    /// @dev The floor guards the worker's CTC: every deposit costs the same to prove
    ///      whatever its size.
    function testDepositBelowTheFloorReverts() external {
        // ARRANGE
        uint256 amount = MIN_DEPOSIT - 1;
        usd.mint(user, amount);

        vm.prank(user);
        usd.approve(address(escrow), amount);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(RiyaEscrow.RiyaEscrow__BelowMinDeposit.selector, amount, MIN_DEPOSIT));
        vm.prank(user);
        escrow.deposit(amount);
    }
}
