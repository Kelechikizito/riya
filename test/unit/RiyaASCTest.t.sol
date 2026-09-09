// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {LoanLedger} from "src/destination-chain/LoanLedger.sol";
import {RiyaASC} from "src/destination-chain/RiyaASC.sol";
import {RiyaUSD} from "src/destination-chain/RiyaUSD.sol";
import {EvmTxFixture} from "test/helpers/EvmTxFixture.sol";
import {MockNativeQueryVerifier} from "test/mocks/MockNativeQueryVerifier.sol";

/// @notice Covers the three checks the precompile does not perform: replay, receipt status,
///         and the emitter pin. Dropping any one makes the protocol drainable.
/// @dev The precompile is native code that exists only on Creditcoin, so a mock is etched
///      at `0x0FD2`. `encodedTransaction` is real ABI-encoded bytes from `EvmTxFixture`,
///      not a stub, so `EvmV1Decoder` runs for real on every one of these.
contract RiyaASCTest is Test {
    event ProofConsumed(bytes32 indexed key, RiyaASC.RiyaASCActions indexed action, uint256 value);

    bytes32 constant DEPOSIT_SIG = keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");
    bytes32 constant HARVEST_SIG = keccak256("TokensHarvested(address,uint256)");

    uint64 constant CHAIN_KEY = 1;
    uint64 constant HEIGHT = 9_123_456;

    RiyaASC asc;
    LoanLedger ledger;
    RiyaUSD riyaUSD;
    MockNativeQueryVerifier verifier;

    address escrow = makeAddr("escrow");
    address adapter = makeAddr("adapter");
    address alice = makeAddr("alice");
    address impostor = makeAddr("impostor");
    address relayer = makeAddr("relayer");

    function setUp() public {
        // The precompile has no bytecode locally, so put a mock where the library looks.
        verifier = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE, address(verifier).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE);
        verifier.setValid(true);
        verifier.setTxIndex(7);

        uint256 nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 2);

        riyaUSD = new RiyaUSD(predictedLedger);
        asc = new RiyaASC(CHAIN_KEY, escrow, adapter, predictedLedger);
        ledger = new LoanLedger(address(asc), riyaUSD);

        assertEq(address(ledger), predictedLedger);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorStoresEveryPin() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertEq(asc.I_CHAIN_KEY(), CHAIN_KEY);
        assertEq(asc.I_ESCROW_CONTRACT(), escrow);
        assertEq(asc.I_ADAPTER_CONTRACT(), adapter);
        assertEq(address(asc.I_LEDGER()), address(ledger));
        assertEq(address(asc.I_VERIFIER()), NativeQueryVerifierLib.PRECOMPILE);
    }

    function testConstructorRejectsZeroChainKey() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroChainKey.selector);
        new RiyaASC(0, escrow, adapter, address(ledger));
    }

    function testConstructorRejectsZeroEscrow() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroAddress.selector);
        new RiyaASC(CHAIN_KEY, address(0), adapter, address(ledger));
    }

    function testConstructorRejectsZeroAdapter() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroAddress.selector);
        new RiyaASC(CHAIN_KEY, escrow, address(0), address(ledger));
    }

    function testConstructorRejectsZeroLedger() external {
        // ARRANGE
        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroAddress.selector);
        new RiyaASC(CHAIN_KEY, escrow, adapter, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                              HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function testProvenDepositBecomesCollateral() external {
        // ARRANGE
        bytes memory encoded = _depositTx(escrow, alice, 1_000e6);

        // ACT
        vm.expectEmit(true, true, false, true, address(asc));
        emit ProofConsumed(_key(HEIGHT, 7), RiyaASC.RiyaASCActions.EscrowDeposited, 1_000e6);

        _submit(HEIGHT, encoded);

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
        assertTrue(asc.isConsumed(_key(HEIGHT, 7)));
    }

    function testProvenHarvestDistributesYield() external {
        // ARRANGE
        _submit(HEIGHT, _depositTx(escrow, alice, 1_000e6));
        verifier.setTxIndex(8);

        // ACT
        _submit(HEIGHT + 1, _harvestTx(adapter, relayer, 100e6));

        // ASSERT
        assertEq(ledger.s_protocolFees(), 15e6);
        assertEq(ledger.pendingYield(alice), 85e6);
    }

    /// @dev A valid proof is valid whoever carries it. Gating this would mean trusting the
    ///      worker's key rather than the cryptography.
    function testSubmitIsPermissionless() external {
        // ARRANGE
        bytes memory encoded = _depositTx(escrow, alice, 1_000e6);

        // ACT
        vm.prank(makeAddr("stranger"));
        asc.submit(HEIGHT, encoded, _merkleProof(), _continuityProof());

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
    }

    /// @dev One transaction may carry many logs, and all of them must apply.
    function testMultipleDepositLogsInOneTransactionAllApply() external {
        // ARRANGE
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(600e6))));
        logs[1] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(400e6))));

        // ACT
        _submit(HEIGHT, EvmTxFixture.encode(1, logs));

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
    }

    /// @dev Harvests run before deposits, so a depositor arriving in the same transaction
    ///      does not share yield that accrued before they existed.
    function testHarvestIsAppliedBeforeADepositInTheSameTransaction() external {
        // ARRANGE
        address bob = makeAddr("bob");
        _submit(HEIGHT, _depositTx(escrow, bob, 1_000e6));
        verifier.setTxIndex(8);

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(1_000e6))));
        logs[1] = EvmTxFixture.log(adapter, EvmTxFixture.topics3(HARVEST_SIG, _b32(relayer), bytes32(uint256(100e6))));

        // ACT
        _submit(HEIGHT + 1, EvmTxFixture.encode(1, logs));

        // ASSERT
        assertEq(ledger.pendingYield(bob), 85e6, "the yield went entirely to the earlier depositor");
        assertEq(ledger.pendingYield(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              THE THREE CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Proof bytes are public and `submit` is permissionless, so without this one real
    ///      harvest could be replayed until every borrower's debt hit zero.
    function testReplayingTheSameProofReverts() external {
        // ARRANGE
        bytes memory encoded = _depositTx(escrow, alice, 1_000e6);
        _submit(HEIGHT, encoded);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(RiyaASC.RiyaASC__AlreadyConsumed.selector, _key(HEIGHT, 7)));
        _submit(HEIGHT, encoded);
    }

    /// @dev A reverted transaction still sits in a block and still proves cleanly.
    function testRevertedSourceTransactionIsRejected() external {
        // ARRANGE
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(1_000e6))));
        bytes memory encoded = EvmTxFixture.encode(0, logs);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(RiyaASC.RiyaASC__TxReverted.selector, encoded));
        _submit(HEIGHT, encoded);

        assertEq(ledger.s_collateral(alice), 0);
    }

    /// @dev Event signatures are public, so anyone can emit `TokensHarvested` with a value
    ///      of one billion. `log.address_` is the field they cannot forge.
    function testImpostorEmitterIsIgnored() external {
        // ARRANGE
        bytes memory encoded = _harvestTx(impostor, relayer, 1_000_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__NoRelevantLog.selector);
        _submit(HEIGHT, encoded);

        assertEq(ledger.s_yieldPerShare(), 0);
    }

    function testImpostorDepositEmitterIsIgnored() external {
        // ARRANGE
        bytes memory encoded = _depositTx(impostor, alice, 1_000_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__NoRelevantLog.selector);
        _submit(HEIGHT, encoded);

        assertEq(ledger.s_collateral(alice), 0);
    }

    /// @dev The griefing case the `continue` exists for. A fake log beside a real one must
    ///      not block the real one, or anyone could permanently poison a genuine proof.
    function testImpostorLogBesideARealOneDoesNotBlockIt() external {
        // ARRANGE
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] =
            EvmTxFixture.log(impostor, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(999_000e6))));
        logs[1] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(1_000e6))));

        // ACT
        _submit(HEIGHT, EvmTxFixture.encode(1, logs));

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6, "only the real log applied");
    }

    /// @dev A short log shares topic0 but not the shape, and reading `topics[2]` on it
    ///      reverts. Skipping rather than reverting is what stops it being a grief.
    function testMalformedLogIsSkippedNotFatal() external {
        // ARRANGE
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics1(DEPOSIT_SIG));
        logs[1] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(alice), bytes32(uint256(1_000e6))));

        // ACT
        _submit(HEIGHT, EvmTxFixture.encode(1, logs));

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_000e6);
    }

    function testMalformedHarvestLogIsSkipped() external {
        // ARRANGE
        _submit(HEIGHT, _depositTx(escrow, alice, 1_000e6));
        verifier.setTxIndex(8);

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EvmTxFixture.log(adapter, EvmTxFixture.topics1(HARVEST_SIG));
        logs[1] = EvmTxFixture.log(adapter, EvmTxFixture.topics3(HARVEST_SIG, _b32(relayer), bytes32(uint256(100e6))));

        // ACT
        _submit(HEIGHT + 1, EvmTxFixture.encode(1, logs));

        // ASSERT
        assertEq(ledger.pendingYield(alice), 85e6);
    }

    /*//////////////////////////////////////////////////////////////
                              OTHER GUARDS
    //////////////////////////////////////////////////////////////*/

    function testZeroHeightReverts() external {
        // ARRANGE
        bytes memory encoded = _depositTx(escrow, alice, 1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroHeight.selector);
        _submit(0, encoded);
    }

    function testProofThePrecompileRejectsReverts() external {
        // ARRANGE
        verifier.setValid(false);
        bytes memory encoded = _depositTx(escrow, alice, 1_000e6);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ProofInvalid.selector);
        _submit(HEIGHT, encoded);
    }

    /// @dev A transaction with nothing riya cares about should never have been submitted.
    ///      Failing loudly stops someone burning CTC on unrelated proofs.
    function testTransactionWithNoRiyaLogsReverts() external {
        // ARRANGE
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(keccak256("Transfer(address,address,uint256)"), 0, 0));

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__NoRelevantLog.selector);
        _submit(HEIGHT, EvmTxFixture.encode(1, logs));
    }

    function testIsConsumedIsFalseForAnUnseenKey() external view {
        // ARRANGE
        // ACT
        // ASSERT
        assertFalse(asc.isConsumed(_key(HEIGHT, 7)));
    }

    /// @dev Same block, different transaction index, so a different key. Two real deposits
    ///      in one block must both apply.
    function testDifferentTxIndexInTheSameBlockIsADifferentProof() external {
        // ARRANGE
        _submit(HEIGHT, _depositTx(escrow, alice, 1_000e6));

        // ACT
        verifier.setTxIndex(9);
        _submit(HEIGHT, _depositTx(escrow, alice, 500e6));

        // ASSERT
        assertEq(ledger.s_collateral(alice), 1_500e6);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _submit(uint64 height, bytes memory encoded) internal {
        asc.submit(height, encoded, _merkleProof(), _continuityProof());
    }

    function _depositTx(address emitter, address user, uint256 assets) internal pure returns (bytes memory) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmTxFixture.log(emitter, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(user), bytes32(assets)));
        return EvmTxFixture.encode(1, logs);
    }

    function _harvestTx(address emitter, address caller, uint256 gross) internal pure returns (bytes memory) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmTxFixture.log(emitter, EvmTxFixture.topics3(HARVEST_SIG, _b32(caller), bytes32(gross)));
        return EvmTxFixture.encode(1, logs);
    }

    /// @dev The same fingerprint `submit` computes, and the same one the worker rebuilds
    ///      off-chain to skip a resubmission. `abi.encode`, never `abi.encodePacked`.
    function _key(uint64 height, uint64 txIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(CHAIN_KEY, height, _merkleProof().root, txIndex));
    }

    function _merkleProof() internal pure returns (INativeQueryVerifier.MerkleProof memory) {
        return INativeQueryVerifier.MerkleProof({
            root: bytes32(uint256(0x1111)), siblings: new INativeQueryVerifier.MerkleProofEntry[](0)
        });
    }

    function _continuityProof() internal pure returns (INativeQueryVerifier.ContinuityProof memory) {
        return INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(0), roots: new bytes32[](0)});
    }

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }
}
