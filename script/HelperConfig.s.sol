// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/**
 * @title HelperConfig
 * @author Kelechi Kizito Ugwu
 * @notice Per-chain deployment parameters for riya's source-chain contracts.
 * @dev Aave V4 is live on Ethereum mainnet but has no testnet deployment, so the two
 *      chains riya targets need genuinely different configs: mainnet points at the real
 *      Spoke, Sepolia points at a `MockAaveSpoke` you deploy yourself. Keeping that
 *      split here means the deploy script never learns which chain it is on.
 *
 *      The asset is deliberately absent — it is read from the Spoke's reserve at
 *      construction, so there is no second copy of it to disagree.
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error HelperConfig__UnsupportedChain(uint256 chainId);

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @param spoke The Aave V4 Spoke to supply through, exists on mainnet but mocked on other networks
    /// @param reserveId The reserve's index within `spoke`.
    /// @param minHarvest Smallest harvest worth Ethereum gas.
    /// @param minDeposit Smallest deposit worth a Creditcoin proof. Guards the worker's CTC.
    struct NetworkConfig {
        address spoke;
        uint256 reserveId;
        uint256 minHarvest;
        uint256 minDeposit;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS & STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    NetworkConfig public activeNetworkConfig;

    uint256 private constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 private constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 private constant LOCAL_CHAIN_ID = 31337;
    uint256 private constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Aave V4 "Main Spoke". Verified against the Aave address book.
    address private constant MAINNET_SPOKE =
        0x94e7A5dCbE816e498b89aB752661904E2F56c485;

    /// @dev USDC's index on `MAINNET_SPOKE`, confirmed on-chain: underlying is USDC,
    ///      decimals 6, hub is the Core Hub. Ids only ever increase, so this is stable.
    uint256 private constant MAINNET_USDC_RESERVE_ID = 7;

    /// @dev USDC has 6 decimals, so these are 10 and 100 dollars.
    uint256 private constant MIN_HARVEST = 10e6;
    uint256 private constant MIN_DEPOSIT = 100e6;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == ETH_MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == LOCAL_CHAIN_ID) {
            activeNetworkConfig = getAnvilConfig();
        } else {
            revert HelperConfig__UnsupportedChain(block.chainid);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // /// @notice The config for whichever chain this script is running against.
    // /// @dev Reverts rather than falling back to a default — a silently wrong Spoke would
    // ///      deploy an adapter pointed at the wrong protocol.
    // function getConfig() public view returns (NetworkConfig memory) {
    //     if (block.chainid == ETH_MAINNET_CHAIN_ID) return getMainnetConfig();
    //     if (block.chainid == ETH_SEPOLIA_CHAIN_ID) return getSepoliaConfig();
    //     if (block.chainid == LOCAL_CHAIN_ID) return getAnvilConfig();
    //     revert HelperConfig__UnsupportedChain(block.chainid);
    // }

    /// @notice Real Aave V4. Used by the mainnet fork tests, not by the demo.
    function getMainnetConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                spoke: MAINNET_SPOKE,
                reserveId: MAINNET_USDC_RESERVE_ID,
                minHarvest: MIN_HARVEST,
                minDeposit: MIN_DEPOSIT
            });
    }

    /// @notice The demo chain. Aave V4 is not deployed here, so `MOCK_SPOKE` is a
    ///         `MockAaveSpoke` deployed separately; put its address in `.env`.
    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                spoke: vm.envAddress("MOCK_SPOKE"),
                reserveId: vm.envUint("MOCK_RESERVE_ID"),
                minHarvest: MIN_HARVEST,
                minDeposit: MIN_DEPOSIT
            });
    }

    /// @notice Local anvil. Deploys its own mocks so tests need no network.
    /// @dev TODO(checkpoint 9): deploy `MockAaveSpoke` here and return its address.
    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        revert HelperConfig__UnsupportedChain(LOCAL_CHAIN_ID);
    }
}
