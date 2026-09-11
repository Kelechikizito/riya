// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveV4Adapter} from "src/adapters/AaveV4Adapter.sol";
import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {RiyaEscrow} from "src/source-chain/ethereum/RiyaEscrow.sol";
import {DeployRiyaSourceChain} from "script/deployment/DeployRiyaSourceChain.s.sol";
import {DeployRiyaDestinationChain} from "script/deployment/DeployRiyaDestinationChain.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {HelperConfigDestination} from "script/HelperConfigDestination.s.sol";
import {MockChainInfo} from "test/mocks/MockChainInfo.sol";
import {SharedEnv} from "test/helpers/SharedEnv.sol";

/**
 * @dev Two jobs.
 *
 *      It exposes each script's internal prediction check, because a shifted nonce cannot be
 *      produced from outside a script that reads and consumes its own nonces in one call.
 *
 *      It also pins `_broadcaster` to forge's `DEFAULT_SENDER`. Under `forge script --sender`
 *      that address is both the sender and `msg.sender`, but in a test `vm.startBroadcast()`
 *      broadcasts from `DEFAULT_SENDER` while `msg.sender` is whoever called `run()`. Without
 *      the override the script predicts against one address and deploys from another.
 */
contract SourceDeployHarness is DeployRiyaSourceChain {
    function assertPrediction(address predicted, address actual) external pure {
        _assertPrediction(predicted, actual);
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }
}

contract DestinationDeployHarness is DeployRiyaDestinationChain {
    function assertPrediction(address predicted, address actual) external pure {
        _assertPrediction(predicted, actual);
    }

    function _broadcaster() internal pure override returns (address) {
        return DEFAULT_SENDER;
    }
}

/**
 * @title DeployScriptsTest
 * @author Kelechi Kizito Ugwu
 * @notice Runs both deploy scripts and checks what they wire together.
 * @dev Every pin in riya is `immutable`, so a script that mis-wires one does not fail at
 *      deploy time. It produces contracts that verify cleanly on a block explorer and then
 *      reject every proof forever. These tests are the only place that can catch it.
 */
contract DeployScriptsTest is Test {
    uint256 constant ANVIL = 31337;
    uint256 constant CREDITCOIN_TESTNET = 102031;
    uint64 constant ETH_SEPOLIA = 11155111;

    /// @dev The Chain Info Precompile. Same address on every Creditcoin network.
    address constant CHAIN_INFO = 0x0000000000000000000000000000000000000fD3;

    /// @dev Whoever `vm.startBroadcast()` sends from in a test. See `SourceDeployHarness`.
    address deployer = DEFAULT_SENDER;

    /// @dev From `SharedEnv`, not `makeAddr`. `vm.setEnv` is process-global and test
    ///      contracts run in parallel, so two suites writing different values to
    ///      `RIYA_ESCROW_ADDRESS` race and fail intermittently.
    address constant escrowOnEthereum = SharedEnv.ESCROW;
    address constant adapterOnEthereum = SharedEnv.ADAPTER;

    /*//////////////////////////////////////////////////////////////
                              SOURCE CHAIN
    //////////////////////////////////////////////////////////////*/

    /// @dev The adapter's constructor takes an address with no code on it, so the whole
    ///      deployment rests on the nonce prediction being right.
    function testSourceChainDeployWiresThePairBothWays() external {
        // ARRANGE
        vm.chainId(ANVIL);
        SourceDeployHarness script = new SourceDeployHarness();

        // ACT
        (AaveV4Adapter adapter, RiyaEscrow escrow, HelperConfig config) = script.run();

        // ASSERT
        assertTrue(address(config) != address(0), "the config is returned so tests can reuse it");
        assertEq(adapter.I_ESCROW(), address(escrow), "prediction held");
        assertEq(address(escrow.I_ADAPTER()), address(adapter));
        assertEq(address(escrow.I_ASSET()), adapter.asset(), "one asset, read from the Spoke");
        assertEq(adapter.I_MIN_HARVEST(), 10e6);
        assertEq(escrow.I_MIN_DEPOSIT(), 100e6);
    }

    function testSourceChainDeployBroadcastsFromTheConfiguredKey() external {
        // ARRANGE
        vm.chainId(ANVIL);
        SourceDeployHarness script = new SourceDeployHarness();

        // ACT
        (AaveV4Adapter adapter,,) = script.run();

        // ASSERT
        assertEq(vm.computeCreateAddress(deployer, vm.getNonce(deployer) - 2), address(adapter));
    }

    /*//////////////////////////////////////////////////////////////
                           DESTINATION CHAIN
    //////////////////////////////////////////////////////////////*/

    /// @dev Three contracts, all circular. `nonce + 2`, not `nonce + 1`: count deployments
    ///      between the prediction and the ledger, not contracts in the system.
    function testDestinationDeployWiresAllThree() external {
        // ARRANGE
        _prepareCreditcoin();
        _registerChain(1, ETH_SEPOLIA);
        DestinationDeployHarness script = new DestinationDeployHarness();

        // ACT
        (RiyaUSD riyaUSD, RiyaASC asc, LoanLedger ledger,) = script.run();

        // ASSERT
        assertEq(riyaUSD.I_LEDGER(), address(ledger), "prediction held for the token");
        assertEq(address(asc.I_LEDGER()), address(ledger), "and for the ASC");
        assertEq(address(ledger.I_RIYA_ASC()), address(asc));
        assertEq(address(ledger.I_RIYA_USD()), address(riyaUSD));

        assertEq(asc.I_CHAIN_KEY(), 1);
        assertEq(asc.I_ESCROW_CONTRACT(), escrowOnEthereum);
        assertEq(asc.I_ADAPTER_CONTRACT(), adapterOnEthereum);
    }

    /// @dev The deployed system must actually work, not merely hold the right addresses.
    function testDestinationDeployProducesAUsableSystem() external {
        // ARRANGE
        _prepareCreditcoin();
        _registerChain(1, ETH_SEPOLIA);
        DestinationDeployHarness script = new DestinationDeployHarness();
        (RiyaUSD riyaUSD, RiyaASC asc, LoanLedger ledger,) = script.run();

        // ACT
        address alice = makeAddr("alice");
        vm.prank(address(asc));
        ledger.onDeposit(alice, 1_000e6);

        vm.prank(alice);
        ledger.borrow(100e6);

        // ASSERT
        assertEq(riyaUSD.balanceOf(alice), 100e6, "the mint lock accepts the real ledger");
    }

    /// @dev The failure this check exists for. `RiyaASC` rejects a zero chain key but cannot
    ///      tell 1 from 3, and the value is immutable, so a key resolving to the wrong chain
    ///      deploys cleanly and then reads Ethereum Mainnet when the escrow is on Sepolia.
    function testDestinationDeployRejectsAChainKeyPointingAtTheWrongChain() external {
        // ARRANGE
        _prepareCreditcoin();
        _registerChain(1, 1); // key 1 resolves to Ethereum Mainnet, not Sepolia
        DestinationDeployHarness script = new DestinationDeployHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaDestinationChain.DeployRiyaDestinationChain__ChainKeyMismatch.selector,
                uint64(1),
                ETH_SEPOLIA,
                uint64(1)
            )
        );
        script.run();
    }

    /// @dev Almost always a testnet key used against Mainnet, or the reverse.
    function testDestinationDeployRejectsAnUnregisteredChainKey() external {
        // ARRANGE
        _prepareCreditcoin();
        _registerChain(3, ETH_SEPOLIA); // the registry knows 3, the config asks for 1
        DestinationDeployHarness script = new DestinationDeployHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaDestinationChain.DeployRiyaDestinationChain__UnknownChainKey.selector, uint64(1)
            )
        );
        script.run();
    }

    /// @dev The check runs before `startBroadcast`, so a bad key costs no gas at all.
    function testChainKeyIsCheckedBeforeAnythingIsDeployed() external {
        // ARRANGE
        _prepareCreditcoin();
        _registerChain(1, 1);
        DestinationDeployHarness script = new DestinationDeployHarness();
        uint256 nonceBefore = vm.getNonce(deployer);

        // ACT
        vm.expectRevert();
        script.run();

        // ASSERT
        assertEq(vm.getNonce(deployer), nonceBefore, "nothing was deployed");
    }

    /*//////////////////////////////////////////////////////////////
                          PREDICTION ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    function testSourcePredictionCheckPassesOnAMatch() external {
        // ARRANGE
        SourceDeployHarness harness = new SourceDeployHarness();

        // ACT
        // ASSERT
        harness.assertPrediction(escrowOnEthereum, escrowOnEthereum);
    }

    function testSourcePredictionCheckRevertsOnAMismatch() external {
        // ARRANGE
        SourceDeployHarness harness = new SourceDeployHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaSourceChain.DeployRiyaSourceChain__PredictionMissed.selector,
                escrowOnEthereum,
                adapterOnEthereum
            )
        );
        harness.assertPrediction(escrowOnEthereum, adapterOnEthereum);
    }

    function testDestinationPredictionCheckPassesOnAMatch() external {
        // ARRANGE
        DestinationDeployHarness harness = new DestinationDeployHarness();

        // ACT
        // ASSERT
        harness.assertPrediction(escrowOnEthereum, escrowOnEthereum);
    }

    function testDestinationPredictionCheckRevertsOnAMismatch() external {
        // ARRANGE
        DestinationDeployHarness harness = new DestinationDeployHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaDestinationChain.DeployRiyaDestinationChain__PredictionMissed.selector,
                escrowOnEthereum,
                adapterOnEthereum
            )
        );
        harness.assertPrediction(escrowOnEthereum, adapterOnEthereum);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _prepareCreditcoin() internal {
        vm.chainId(CREDITCOIN_TESTNET);
        vm.setEnv("RIYA_ESCROW_ADDRESS", vm.toString(escrowOnEthereum));
        vm.setEnv("AAVE_V4_ADAPTER_ADDRESS", vm.toString(adapterOnEthereum));

        MockChainInfo template = new MockChainInfo();
        vm.etch(CHAIN_INFO, address(template).code);
    }

    function _registerChain(uint64 chainKey, uint64 chainId) internal {
        MockChainInfo(CHAIN_INFO).addChain(chainKey, chainId);
    }
}
