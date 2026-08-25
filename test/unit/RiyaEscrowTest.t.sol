// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// 1. Write Fork tests:  Fork-test against mainnet — against the real Spoke. Real V4, real reserve, no deploy.
// Proves the adapter works; can't be the live demo.
contract RiyaEscrowTest is Test {
    using SafeERC20 for IERC20;
    uint256 ethMainnetFork;
    uint256 ethSepoliaFork;

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

    function setUp() public {}
}
