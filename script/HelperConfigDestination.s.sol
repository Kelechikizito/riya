// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/**
 * @title HelperConfigDestination
 * @author Kelechi Kizito Ugwu
 * @notice Per-chain deployment parameters for riya's Creditcoin contracts.
 * @dev Separate from `HelperConfig` because the two sides share no parameters. One struct
 *      covering both would be half-empty whichever chain you deployed to.
 *
 *      `escrow` and `adapter` exist only after `DeployRiyaSourceChain` has run, so they
 *      come from `.env`: this script cannot deploy them.
 */
contract HelperConfigDestination is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error HelperConfigDestination__UnsupportedChain(uint256 chainId);

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @param chainKey Creditcoin's identifier for the source chain, in this network's
    ///        own registry.
    /// @param sourceChainId The EVM chain id `chainKey` must resolve to, so the deploy
    ///        script can prove the key rather than trust it.
    /// @param escrow `RiyaEscrow` on Ethereum, the only accepted deposit emitter.
    /// @param adapter `AaveV4Adapter` on Ethereum, the only accepted harvest emitter.
    struct DestinationConfig {
        uint64 chainKey;
        uint64 sourceChainId;
        address escrow;
        address adapter;
    }

    /*//////////////////////////////////////////////////////////////
                       CONSTANTS & STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DestinationConfig public activeNetworkConfig;

    uint256 private constant CREDITCOIN_TESTNET_CHAIN_ID = 102031;
    uint256 private constant CREDITCOIN_MAINNET_CHAIN_ID = 102030;

    uint64 private constant ETH_MAINNET_CHAIN_ID = 1;
    uint64 private constant ETH_SEPOLIA_CHAIN_ID = 11155111;

    /// @dev Creditcoin Testnet's registry: Sepolia is 1, Ethereum Mainnet is 3.
    uint64 private constant TESTNET_SEPOLIA_CHAIN_KEY = 1;

    /// @dev Creditcoin Mainnet numbers Ethereum Mainnet as 1. Same number as the entry
    ///      above, different chain. Coincidence, not a pattern.
    uint64 private constant MAINNET_ETHEREUM_CHAIN_KEY = 1;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        if (block.chainid == CREDITCOIN_TESTNET_CHAIN_ID) {
            activeNetworkConfig = getCreditcoinTestnetConfig();
        } else if (block.chainid == CREDITCOIN_MAINNET_CHAIN_ID) {
            activeNetworkConfig = getCreditcoinMainnetConfig();
        } else {
            revert HelperConfigDestination__UnsupportedChain(block.chainid);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The demo chain, reading Ethereum Sepolia.
    function getCreditcoinTestnetConfig() public view returns (DestinationConfig memory) {
        return DestinationConfig({
            chainKey: TESTNET_SEPOLIA_CHAIN_KEY,
            sourceChainId: ETH_SEPOLIA_CHAIN_ID,
            escrow: vm.envAddress("RIYA_ESCROW_ADDRESS"),
            adapter: vm.envAddress("AAVE_V4_ADAPTER_ADDRESS")
        });
    }

    /// @notice The production chain, reading Ethereum Mainnet.
    function getCreditcoinMainnetConfig() public view returns (DestinationConfig memory) {
        return DestinationConfig({
            chainKey: MAINNET_ETHEREUM_CHAIN_KEY,
            sourceChainId: ETH_MAINNET_CHAIN_ID,
            escrow: vm.envAddress("RIYA_ESCROW_ADDRESS"),
            adapter: vm.envAddress("AAVE_V4_ADAPTER_ADDRESS")
        });
    }
}
