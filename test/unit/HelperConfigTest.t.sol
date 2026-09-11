// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {HelperConfig} from "script/HelperConfig.s.sol";
import {HelperConfigDestination} from "script/HelperConfigDestination.s.sol";
import {MockAaveSpoke} from "test/mocks/MockAaveSpoke.sol";
import {MockUSD} from "test/mocks/MockUSD.sol";
import {SharedEnv} from "test/helpers/SharedEnv.sol";

/// @notice Covers both config contracts on every chain they claim to support, and the
///         revert on every chain they do not.
/// @dev These decide what gets deployed and against which chain's registry, so a wrong
///      branch here is a deployment pointed at the wrong network, not a failing test.
contract HelperConfigTest is Test {
    uint256 constant ETH_MAINNET = 1;
    uint256 constant ETH_SEPOLIA = 11155111;
    uint256 constant ANVIL = 31337;
    uint256 constant CREDITCOIN_TESTNET = 102031;
    uint256 constant CREDITCOIN_MAINNET = 102030;

    address constant MAINNET_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;

    /// @dev From `SharedEnv`, not `makeAddr`. See that file: `vm.setEnv` is process-global
    ///      and test contracts run in parallel, so every suite writes the same values.
    address constant escrow = SharedEnv.ESCROW;
    address constant adapter = SharedEnv.ADAPTER;

    /*//////////////////////////////////////////////////////////////
                              SOURCE CHAIN
    //////////////////////////////////////////////////////////////*/

    /// @dev Anvil deploys its own pair, so a local run needs no network and no `.env`.
    function testAnvilConfigDeploysAListedReserve() external {
        // ARRANGE
        vm.chainId(ANVIL);

        // ACT
        HelperConfig config = new HelperConfig();
        (address spoke, uint256 reserveId, uint256 minHarvest, uint256 minDeposit) = config.activeNetworkConfig();

        // ASSERT
        assertTrue(spoke != address(0));
        assertEq(reserveId, 1, "reserve ids start at 1");
        assertEq(minHarvest, 10e6);
        assertEq(minDeposit, 100e6);

        MockUSD usd = MockUSD(MockAaveSpoke(spoke).getReserve(reserveId).underlying);
        assertEq(usd.decimals(), 6);
    }

    /// @dev Called twice, it must hand back the pair it already deployed. Deploying a second
    ///      one would strand the first and return an empty reserve.
    function testAnvilConfigDoesNotRedeployOnASecondCall() external {
        // ARRANGE
        vm.chainId(ANVIL);
        HelperConfig config = new HelperConfig();
        (address first,,,) = config.activeNetworkConfig();

        // ACT
        HelperConfig.NetworkConfig memory second = config.getAnvilConfig();

        // ASSERT
        assertEq(second.spoke, first);
    }

    function testMainnetConfigPointsAtRealAaveV4() external {
        // ARRANGE
        vm.chainId(ETH_MAINNET);

        // ACT
        HelperConfig config = new HelperConfig();
        (address spoke, uint256 reserveId,,) = config.activeNetworkConfig();

        // ASSERT
        assertEq(spoke, MAINNET_SPOKE);
        assertEq(reserveId, 7, "USDC's index on the Main Spoke");
    }

    /// @dev Aave V4 is not deployed on Sepolia, so the spoke comes from `.env` and is a
    ///      `MockAaveSpoke` deployed separately.
    function testSepoliaConfigReadsTheMockFromEnv() external {
        // ARRANGE
        vm.chainId(ETH_SEPOLIA);
        vm.setEnv("MOCK_SPOKE", vm.toString(SharedEnv.MOCK_SPOKE));
        vm.setEnv("MOCK_RESERVE_ID", vm.toString(SharedEnv.MOCK_RESERVE_ID));

        // ACT
        HelperConfig config = new HelperConfig();
        (address spoke, uint256 reserveId, uint256 minHarvest, uint256 minDeposit) = config.activeNetworkConfig();

        // ASSERT
        assertEq(spoke, SharedEnv.MOCK_SPOKE);
        assertEq(reserveId, SharedEnv.MOCK_RESERVE_ID);
        assertEq(minHarvest, 10e6, "thresholds match the live chains");
        assertEq(minDeposit, 100e6);
    }

    function testSourceConfigRejectsAnUnsupportedChain() external {
        // ARRANGE
        vm.chainId(8453);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(HelperConfig.HelperConfig__UnsupportedChain.selector, 8453));
        new HelperConfig();
    }

    /*//////////////////////////////////////////////////////////////
                           DESTINATION CHAIN
    //////////////////////////////////////////////////////////////*/

    function testCreditcoinTestnetReadsSepolia() external {
        // ARRANGE
        vm.chainId(CREDITCOIN_TESTNET);
        _setSourceAddresses();

        // ACT
        HelperConfigDestination config = new HelperConfigDestination();
        (uint64 chainKey, uint64 sourceChainId, address e, address a) = config.activeNetworkConfig();

        // ASSERT
        assertEq(chainKey, 1, "Sepolia is 1 in the testnet registry");
        assertEq(sourceChainId, ETH_SEPOLIA);
        assertEq(e, escrow);
        assertEq(a, adapter);
    }

    function testCreditcoinMainnetReadsEthereumMainnet() external {
        // ARRANGE
        vm.chainId(CREDITCOIN_MAINNET);
        _setSourceAddresses();

        // ACT
        HelperConfigDestination config = new HelperConfigDestination();
        (uint64 chainKey, uint64 sourceChainId,,) = config.activeNetworkConfig();

        // ASSERT
        assertEq(chainKey, 1, "same number as testnet, different chain");
        assertEq(sourceChainId, ETH_MAINNET);
    }

    /// @dev Ethereum is the only source chain, so a Creditcoin config must not exist for
    ///      anything else, and the destination config must not exist off Creditcoin.
    function testDestinationConfigRejectsAnUnsupportedChain() external {
        // ARRANGE
        vm.chainId(ETH_SEPOLIA);

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                HelperConfigDestination.HelperConfigDestination__UnsupportedChain.selector, ETH_SEPOLIA
            )
        );
        new HelperConfigDestination();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setSourceAddresses() internal {
        vm.setEnv("RIYA_ESCROW_ADDRESS", vm.toString(escrow));
        vm.setEnv("AAVE_V4_ADAPTER_ADDRESS", vm.toString(adapter));
    }
}
