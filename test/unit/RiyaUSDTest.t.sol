// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";

/// @notice Covers the mint and burn lock, and the decimals override.
contract RiyaUSDTest is Test {
    RiyaUSD riyaUSD;

    address ledger = makeAddr("ledger");
    address alice = makeAddr("alice");

    function setUp() public {
        riyaUSD = new RiyaUSD(ledger);
    }

    function testMetadataAndDecimals() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(riyaUSD.name(), "Riya USD");
        assertEq(riyaUSD.symbol(), "rUSD");
        assertEq(riyaUSD.decimals(), 6, "one unit of account, and it is USDC's");
        assertEq(riyaUSD.I_LEDGER(), ledger);
    }

    function testConstructorRejectsZeroLedger() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaUSD.RiyaUSD__ZeroAddress.selector);
        new RiyaUSD(address(0));
    }

    function testLedgerCanMint() external {
        // ARRANGE
        // ACT
        vm.prank(ledger);
        riyaUSD.mint(alice, 100e6);

        // ASSERT
        assertEq(riyaUSD.balanceOf(alice), 100e6);
        assertEq(riyaUSD.totalSupply(), 100e6);
    }

    function testLedgerCanBurnWithoutAllowance() external {
        // ARRANGE
        vm.prank(ledger);
        riyaUSD.mint(alice, 100e6);

        // ACT
        vm.prank(ledger);
        riyaUSD.burn(alice, 40e6);

        // ASSERT
        assertEq(riyaUSD.balanceOf(alice), 60e6);
        assertEq(riyaUSD.allowance(alice, ledger), 0, "no allowance was spent");
    }

    function testNonLedgerCannotMint() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaUSD.RiyaUSD__NotLedger.selector);
        vm.prank(alice);
        riyaUSD.mint(alice, 100e6);
    }

    function testNonLedgerCannotBurn() external {
        // ARRANGE
        vm.prank(ledger);
        riyaUSD.mint(alice, 100e6);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaUSD.RiyaUSD__NotLedger.selector);
        vm.prank(alice);
        riyaUSD.burn(alice, 100e6);
    }

    /// @dev Reverts rather than clamping, so an over-burn is a bug in the ledger and not a
    ///      silently smaller repayment.
    function testBurnBeyondBalanceReverts() external {
        // ARRANGE
        vm.prank(ledger);
        riyaUSD.mint(alice, 100e6);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 100e6, 101e6));
        vm.prank(ledger);
        riyaUSD.burn(alice, 101e6);
    }

    /// @dev An ordinary ERC-20 once minted. Nothing about the lock restricts holders.
    function testHoldersCanTransferFreely() external {
        // ARRANGE
        vm.prank(ledger);
        riyaUSD.mint(alice, 100e6);

        // ACT
        vm.prank(alice);
        riyaUSD.transfer(makeAddr("bob"), 30e6);

        // ASSERT
        assertEq(riyaUSD.balanceOf(alice), 70e6);
        assertEq(riyaUSD.balanceOf(makeAddr("bob")), 30e6);
    }
}
