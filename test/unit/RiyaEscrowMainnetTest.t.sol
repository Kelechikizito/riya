// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";

/// @notice Forks Ethereum Mainnet and runs the adapter against real Aave V4.
/// @dev Proves the adapter works; cannot be the demo, since V4 is deployed nowhere else.
contract RiyaEscrowMainnetTest is Test {
    using SafeERC20 for IERC20;

    event TokensDepositedConfirmedByAdapter(uint256 indexed assets, uint256 indexed shares);
    event TokensDepositedConfirmedByEscrow(address indexed user, uint256 indexed assets);

    uint256 ethMainnetFork;
    AaveV4Adapter aaveAdapter;
    RiyaEscrow escrow;

    /// @dev Aave V4 "Main Spoke". Verified against the Aave address book.
    address private constant MAINNET_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;

    /// @dev USDC's index on `MAINNET_SPOKE`, confirmed on-chain. Ids only ever increase.
    uint256 private constant MAINNET_USDC_RESERVE_ID = 7;

    address private constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev USDC has 6 decimals, so these are 10 and 100 dollars.
    uint256 private constant MIN_HARVEST = 10e6;
    uint256 private constant MIN_DEPOSIT = 100e6;

    address public user = makeAddr("user");
    uint256 userUsdcBalance = 1000e6;
    uint256 userEthBalance = 1 ether;

    address predictedEscrow;

    function setUp() public {
        ethMainnetFork = vm.createSelectFork("mainnet_eth");

        uint256 nonce = vm.getNonce(user);
        predictedEscrow = vm.computeCreateAddress(user, nonce + 1);

        vm.prank(user);
        aaveAdapter =
            new AaveV4Adapter(predictedEscrow, IAaveV4Spoke(MAINNET_SPOKE), MAINNET_USDC_RESERVE_ID, MIN_HARVEST);

        vm.prank(user);
        escrow = new RiyaEscrow(address(aaveAdapter), MIN_DEPOSIT);
    }

    function testPredictedEscrowAddressIsTheSameAsActualEscrowAddress() external view {
        // ARRANGE
        // ACT
        // ASSERT
        console2.log("Predicted Escrow Address", predictedEscrow);
        console2.log("Actual Escrow Address", address(escrow));

        assertEq(predictedEscrow, address(escrow));
    }

    function testDepositWorksAndEmitsEvents() external {
        // ARRANGE
        vm.deal(user, userEthBalance);
        deal(MAINNET_USDC, user, userUsdcBalance);

        vm.prank(user);
        IERC20(MAINNET_USDC).forceApprove(address(escrow), userUsdcBalance);

        // ACT
        // Expectations are registered before the call and matched in emission order. The
        // escrow forwards to the adapter first, so the adapter's event fires first. The
        // 5-arg form pins the emitter, so a lookalike from elsewhere will not satisfy it.
        // `shares` is Aave's internal figure and unknown ahead of time, so only topic 1
        // is checked.
        vm.expectEmit(true, false, false, false, address(aaveAdapter));
        emit TokensDepositedConfirmedByAdapter(MIN_DEPOSIT, 0);

        vm.expectEmit(true, true, false, false, address(escrow));
        emit TokensDepositedConfirmedByEscrow(user, MIN_DEPOSIT);

        vm.prank(user);
        escrow.deposit(MIN_DEPOSIT);

        // ASSERT
        assertEq(IERC20(MAINNET_USDC).balanceOf(address(escrow)), 0, "escrow forwards everything");
        assertEq(aaveAdapter.s_principal(), MIN_DEPOSIT);
        assertEq(IERC20(MAINNET_USDC).balanceOf(user), userUsdcBalance - MIN_DEPOSIT);
    }
}
