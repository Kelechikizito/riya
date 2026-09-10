// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {IChainInfo} from "src/interfaces/IChainInfo.sol";
import {DeployRiyaDestinationChain} from "script/deployment/DeployRiyaDestinationChain.s.sol";
import {HelperConfigDestination} from "script/HelperConfigDestination.s.sol";
import {MockChainInfo} from "test/mocks/MockChainInfo.sol";
import {SharedEnv} from "test/helpers/SharedEnv.sol";

/// @dev Exposes the deploy script's internal chain-key check so it can be driven with keys
///      the config would never produce.
contract ChainKeyHarness is DeployRiyaDestinationChain {
    function assertChainKey(uint64 chainKey, uint64 expected) external view {
        _assertChainKey(chainKey, expected);
    }
}

/**
 * @title CreditcoinTestnetForkTest
 * @author Kelechi Kizito Ugwu
 * @notice Checks riya's Creditcoin assumptions against Creditcoin Testnet itself.
 * @dev **Creditcoin's precompiles cannot be forked.** `0x0FD2` and `0x0FD3` are native node
 *      code, not bytecode in state. Forking copies state, so `eth_getCode` returns empty and
 *      both precompiles simply vanish from the fork. Every call into them fails at roughly
 *      3,000 gas, which is a call to an address with no code, not a revert from the
 *      precompile. Do not read that failure as a bug in the contracts.
 *
 *      So this file works two ways, and the split is deliberate:
 *
 *      - Anything that must genuinely execute on Creditcoin goes through `vm.rpc`, which
 *        sends `eth_call` to the node and returns the real answer.
 *      - Anything that needs riya's own contracts deployed runs on the fork, with the chain
 *        info precompile replaced by a stub **seeded from the live registry**. Real data,
 *        local execution.
 *
 *      What this still cannot prove is that riya's bytecode runs on Creditcoin's EVM, since
 *      a fork executes in revm rather than on the node. Only a real deployment settles that.
 *
 *      The fork resolves through the `creditcoin_testnet` alias in `foundry.toml`, so
 *      `CREDITCOIN_RPC_URL` has to be set or this suite fails rather than skipping.
 */
contract CreditcoinTestnetForkTest is Test {
    uint64 constant CHAIN_KEY_SEPOLIA = 1;
    uint64 constant CHAIN_KEY_ETH_MAINNET = 3;
    uint64 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint64 constant ETH_MAINNET_CHAIN_ID = 1;

    uint256 creditCoinRpcUrl;

    string constant CHAIN_INFO_ADDRESS = "0x0000000000000000000000000000000000000fd3";
    string constant BLOCK_PROVER_ADDRESS = "0x0000000000000000000000000000000000000fd2";

    address constant CHAIN_INFO = 0x0000000000000000000000000000000000000fD3;

    RiyaUSD riyaUSD;
    RiyaASC asc;
    LoanLedger ledger;

    address alice = makeAddr("alice");

    function setUp() public {
        creditCoinRpcUrl = vm.createSelectFork("creditcoin_testnet");

        vm.setEnv("PRIVATE_KEY", vm.toString(SharedEnv.DEPLOYER_KEY));
        vm.setEnv("RIYA_ESCROW_ADDRESS", vm.toString(SharedEnv.ESCROW));
        vm.setEnv("AAVE_V4_ADAPTER_ADDRESS", vm.toString(SharedEnv.ADAPTER));
    }

    /*//////////////////////////////////////////////////////////////
                       THE LIVE REGISTRY, OVER RPC
    //////////////////////////////////////////////////////////////*/

    /// @dev The single most dangerous constant in the project. `RiyaASC` cannot tell 1 from
    ///      3, the value is immutable, and a wrong one reads the wrong chain forever. This is
    ///      the only test that checks it against the chain rather than against a comment.
    function testLiveRegistryAgreesWithTheHardcodedChainKeys() external {
        // ARRANGE
        // ACT
        IChainInfo.ChainInfo[] memory chains = _liveRegistry();

        // ASSERT
        assertGt(chains.length, 0, "the registry is not empty");

        bool sawSepolia;
        bool sawMainnet;
        for (uint256 i; i < chains.length; ++i) {
            if (chains[i].chainKey == CHAIN_KEY_SEPOLIA) {
                assertEq(chains[i].chainId, ETH_SEPOLIA_CHAIN_ID, "key 1 is Sepolia on testnet");
                sawSepolia = true;
            }
            if (chains[i].chainKey == CHAIN_KEY_ETH_MAINNET) {
                assertEq(chains[i].chainId, ETH_MAINNET_CHAIN_ID, "key 3 is Ethereum Mainnet");
                sawMainnet = true;
            }
        }

        assertTrue(sawSepolia, "Sepolia is registered");
        assertTrue(sawMainnet, "Ethereum Mainnet is registered");
    }

    /// @dev Ethereum is the only source chain available, so every registered entry must be
    ///      one of the two Ethereum networks. If that ever stops being true, riya's roadmap
    ///      gains an option and this test is where you find out.
    function testEveryRegisteredChainIsEthereum() external {
        // ARRANGE
        // ACT
        IChainInfo.ChainInfo[] memory chains = _liveRegistry();

        // ASSERT
        for (uint256 i; i < chains.length; ++i) {
            assertTrue(
                chains[i].chainId == ETH_MAINNET_CHAIN_ID || chains[i].chainId == ETH_SEPOLIA_CHAIN_ID,
                "no L2s, no alternative L1s"
            );
        }
    }

    /// @dev `IChainInfo` is hand-written from the SDK's JSON. If the selector or the struct
    ///      layout were wrong, the decode below would produce nonsense rather than fail.
    function testTheChainInfoInterfaceDecodesTheLivePrecompile() external {
        // ARRANGE
        // ACT
        IChainInfo.ChainInfo[] memory chains = _liveRegistry();

        // ASSERT
        for (uint256 i; i < chains.length; ++i) {
            assertGt(chains[i].chainKey, 0, "a decoded key is never zero");
            assertGt(chains[i].chainName.length, 0, "and a decoded name is never empty");
            assertEq(chains[i].chainEncoding, 1, "EVM v1 encoding, which is what EvmV1Decoder reads");
        }
    }

    /// @dev The config hardcodes a key per network. The live registry has to agree, or the
    ///      deploy script asserts against the wrong number and passes anyway.
    function testHelperConfigMatchesTheLiveRegistry() external {
        // ARRANGE
        HelperConfigDestination config = new HelperConfigDestination();
        (uint64 chainKey, uint64 sourceChainId,,) = config.activeNetworkConfig();

        // ACT
        IChainInfo.ChainInfo[] memory chains = _liveRegistry();

        // ASSERT
        bool matched;
        for (uint256 i; i < chains.length; ++i) {
            if (chains[i].chainKey == chainKey) {
                assertEq(chains[i].chainId, sourceChainId, "the configured pair is the live pair");
                matched = true;
            }
        }
        assertTrue(matched, "the configured key exists on this network");
    }

    /*//////////////////////////////////////////////////////////////
                    THE BLOCK PROVER, OVER RPC
    //////////////////////////////////////////////////////////////*/

    /// @dev Native precompiles have no bytecode, so `extcodesize` is zero and the usual
    ///      existence check does not apply. Answering a call is the only real test.
    function testBlockProverPrecompileAnswers() external {
        // ARRANGE
        bytes memory callData =
            abi.encodeWithSelector(INativeQueryVerifier.calculateTxIndex.selector, _emptyMerkleProof());

        // ACT
        bytes memory raw = vm.rpc("eth_call", _ethCallParams(BLOCK_PROVER_ADDRESS, callData));

        // ASSERT
        assertEq(abi.decode(raw, (uint64)), 0, "an empty sibling list is transaction zero");
    }

    /**
     * @notice The real precompile rejects an invalid proof by reverting, not by returning
     *         false.
     * @dev This matters to the worker, and it is not what the local tests suggest.
     *      `RiyaASC.submit` reads `if (!verifyAndEmit(...)) revert RiyaASC__ProofInvalid()`,
     *      but the precompile never returns false for a bad Merkle proof: it reverts with
     *      `Error("Merkle proof validation failed")`, so that branch is unreachable on a live
     *      chain and the worker sees a plain string revert instead of a named custom error.
     *
     *      That is the right outcome. The same revert appears when a block is simply not
     *      attested yet, and the worker treats unnamed reverts as retriable. Catching it and
     *      converting it into a named error would make a transient failure look permanent.
     */
    function testTheRealPrecompileRevertsOnAnInvalidProof() external {
        // ARRANGE
        // Spelled out rather than taken from the interface, because `verify` is overloaded
        // and the selector is ambiguous.
        bytes memory callData = abi.encodeWithSignature(
            "verify(uint64,uint64,bytes,(bytes32,(bytes32,bool)[]),(bytes32,bytes32[]))",
            CHAIN_KEY_SEPOLIA,
            uint64(9_123_456),
            hex"02",
            _emptyMerkleProof(),
            _emptyContinuityProof()
        );

        // ACT
        bool reverted;
        try vm.rpc("eth_call", _ethCallParams(BLOCK_PROVER_ADDRESS, callData)) returns (bytes memory) {
            reverted = false;
        } catch {
            reverted = true;
        }

        // ASSERT
        assertTrue(reverted, "a garbage proof is rejected, and it is rejected loudly");
    }

    /*//////////////////////////////////////////////////////////////
                  THE DEPLOY SCRIPT, ON A SEEDED FORK
    //////////////////////////////////////////////////////////////*/

    /// @dev The nearest thing to a deploy rehearsal this repo can run. The registry contents
    ///      are the live ones, read over RPC and planted in a stub, because Foundry cannot
    ///      host a native precompile inside a fork.
    function testDeployScriptRunsAgainstTheLiveRegistryContents() external {
        // ARRANGE
        _seedChainInfoFromLiveRegistry();
        DeployRiyaDestinationChain script = new DeployRiyaDestinationChain();

        // ACT
        (riyaUSD, asc, ledger,) = script.run();

        // ASSERT
        assertEq(riyaUSD.I_LEDGER(), address(ledger), "the prediction held");
        assertEq(address(asc.I_LEDGER()), address(ledger));
        assertEq(address(ledger.I_RIYA_ASC()), address(asc));
        assertEq(asc.I_CHAIN_KEY(), CHAIN_KEY_SEPOLIA);
        assertEq(asc.I_ESCROW_CONTRACT(), SharedEnv.ESCROW);
        assertEq(address(asc.I_VERIFIER()), NativeQueryVerifierLib.PRECOMPILE);
    }

    /// @dev Key 3 is Ethereum Mainnet in the live registry, so pairing it with Sepolia's
    ///      chain id must be rejected. This is the failure the check exists for.
    function testLiveRegistryCatchesAChainKeyPointingAtTheWrongChain() external {
        // ARRANGE
        _seedChainInfoFromLiveRegistry();
        ChainKeyHarness harness = new ChainKeyHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaDestinationChain.DeployRiyaDestinationChain__ChainKeyMismatch.selector,
                CHAIN_KEY_ETH_MAINNET,
                ETH_SEPOLIA_CHAIN_ID,
                ETH_MAINNET_CHAIN_ID
            )
        );
        harness.assertChainKey(CHAIN_KEY_ETH_MAINNET, ETH_SEPOLIA_CHAIN_ID);
    }

    function testLiveRegistryCatchesAnUnknownChainKey() external {
        // ARRANGE
        _seedChainInfoFromLiveRegistry();
        ChainKeyHarness harness = new ChainKeyHarness();

        // ACT
        // ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRiyaDestinationChain.DeployRiyaDestinationChain__UnknownChainKey.selector, uint64(99)
            )
        );
        harness.assertChainKey(99, ETH_SEPOLIA_CHAIN_ID);
    }

    /// @dev Runs the deployed system against Creditcoin's real state: its block number, its
    ///      timestamp, its account set. It does not prove the bytecode runs on Creditcoin's
    ///      own EVM, because a fork executes locally. Only a deployment settles that.
    function testTheDeployedSystemFunctionsOnAForkOfCreditcoin() external {
        // ARRANGE
        _seedChainInfoFromLiveRegistry();
        DeployRiyaDestinationChain script = new DeployRiyaDestinationChain();
        (riyaUSD, asc, ledger,) = script.run();

        // ACT
        vm.prank(address(asc));
        ledger.onDeposit(alice, 1_000e6);

        vm.prank(alice);
        ledger.borrow(100e6);

        vm.prank(address(asc));
        ledger.onHarvest(100e6);

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
        assertEq(riyaUSD.balanceOf(alice), 100e6, "the mint lock works here too");
        assertEq(ledger.pendingYield(alice), 85e6, "the accumulator survives real chain state");
        assertEq(riyaUSD.decimals(), 6);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Executes `get_supported_chains()` on the node itself, where the precompile lives.
    function _liveRegistry() internal returns (IChainInfo.ChainInfo[] memory) {
        bytes memory raw = vm.rpc(
            "eth_call",
            _ethCallParams(CHAIN_INFO_ADDRESS, abi.encodeWithSelector(IChainInfo.get_supported_chains.selector))
        );
        return abi.decode(raw, (IChainInfo.ChainInfo[]));
    }

    /// @dev Plants the live registry's contents at `0x0FD3` inside the fork, so the deploy
    ///      script's check runs against real data even though the precompile is not there.
    function _seedChainInfoFromLiveRegistry() internal {
        IChainInfo.ChainInfo[] memory chains = _liveRegistry();

        MockChainInfo template = new MockChainInfo();
        vm.etch(CHAIN_INFO, address(template).code);

        for (uint256 i; i < chains.length; ++i) {
            MockChainInfo(CHAIN_INFO).addChain(chains[i].chainKey, chains[i].chainId);
        }
    }

    function _ethCallParams(string memory to, bytes memory callData) internal pure returns (string memory) {
        return string.concat('[{"to":"', to, '","data":"', vm.toString(callData), '"},"latest"]');
    }

    function _emptyMerkleProof() internal pure returns (INativeQueryVerifier.MerkleProof memory) {
        return INativeQueryVerifier.MerkleProof({
            root: bytes32(uint256(0x1111)), siblings: new INativeQueryVerifier.MerkleProofEntry[](0)
        });
    }

    function _emptyContinuityProof() internal pure returns (INativeQueryVerifier.ContinuityProof memory) {
        return INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(0), roots: new bytes32[](0)});
    }
}
