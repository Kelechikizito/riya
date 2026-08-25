// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveV4Spoke} from "src/interfaces/IAaveV4Spoke.sol";

// 1. Write Fork tests:  Fork-test against mainnet — against the real Spoke. Real V4, real reserve, no deploy.
// Proves the adapter works; can't be the live demo.
contract RiyaEscrowMainnetTest is Test {
    using SafeERC20 for IERC20;

    event TokensDepositedConfirmedByAdapter(
        uint256 indexed assets,
        uint256 indexed shares
    );
    event TokensDepositedConfirmedByEscrow(
        address indexed user,
        uint256 indexed assets
    );

    uint256 ethMainnetFork;
    AaveV4Adapter aaveAdapter;
    RiyaEscrow escrow;

    /// @dev Aave V4 "Main Spoke". Verified against the Aave address book.
    address private constant MAINNET_SPOKE =
        0x94e7A5dCbE816e498b89aB752661904E2F56c485;
    /// @dev USDC's index on `MAINNET_SPOKE`, confirmed on-chain: underlying is USDC,
    ///      decimals 6, hub is the Core Hub. Ids only ever increase, so this is stable.
    uint256 private constant MAINNET_USDC_RESERVE_ID = 7;
    /// @dev USDC has 6 decimals, so these are 10 and 100 dollars.
    uint256 private constant MIN_HARVEST = 10e6;
    uint256 private constant MIN_DEPOSIT = 100e6;

    address public USER = makeAddr("user");
    uint256 USER_USDC_BALANCE = 1000e6;
    uint256 USER_ETH_BALANCE = 1 ether;

    address predictedEscrow;

    function setUp() public {
        /// @notice create a fork of Ethereum Mainnet network
        ethMainnetFork = vm.createSelectFork("mainnet_eth");

        uint256 nonce = vm.getNonce(USER);
        predictedEscrow = vm.computeCreateAddress(USER, nonce + 1);

        vm.prank(USER);
        aaveAdapter = new AaveV4Adapter(
            predictedEscrow,
            IAaveV4Spoke(MAINNET_SPOKE),
            MAINNET_USDC_RESERVE_ID,
            MIN_HARVEST
        );

        vm.prank(USER);
        escrow = new RiyaEscrow(address(aaveAdapter), MIN_DEPOSIT);
    }

    function testPredictedEscrowAddressIsTheSameAsActualEscrowAddress()
        external
        view
    {
        // ASSERT
        console2.log("Predicted Escrow Address", predictedEscrow);
        console2.log("Actual Escrow Address", address(escrow));

        assertEq(predictedEscrow, address(escrow));
    }

    function testDepositWorksAndEmitsEvents() external {
        // ARRANGE
        /// @notice This is the USDC address on Ethereum Mainnet network
        address ETH_MAINNET_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // ACT
        vm.deal(USER, USER_ETH_BALANCE);
        /// @notice Foundry cheatcode to send tokens to an address
        deal(ETH_MAINNET_USDC_ADDRESS, USER, USER_USDC_BALANCE);

        /// @notice user has to approve YieldAggregator to spend her USDC tokens
        vm.prank(USER);
        IERC20(ETH_MAINNET_USDC_ADDRESS).forceApprove(
            address(escrow),
            USER_USDC_BALANCE
        );

        vm.prank(USER);
        escrow.deposit(MIN_DEPOSIT);

        // ASSERT
    }
}
