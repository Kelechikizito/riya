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

/**
 * @title RiyaASCFuzz
 * @author Kelechi Kizito Ugwu
 * @notice Stateless fuzz over the replay key and the emitter pin.
 * @dev The replay key is the one piece of arithmetic shared between this contract and the
 *      off-chain worker, and neither side can see the other's version. A collision would let
 *      one real proof block a different real one; a mismatch would make `isConsumed` always
 *      answer no and the worker re-pay for work it already did. Both are silent.
 */
contract RiyaASCFuzz is Test {
    bytes32 constant DEPOSIT_SIG = keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");
    bytes32 constant HARVEST_SIG = keccak256("TokensHarvested(address,uint256)");

    uint64 constant CHAIN_KEY = 1;

    RiyaASC asc;
    LoanLedger ledger;
    RiyaUSD riyaUSD;
    MockNativeQueryVerifier verifier;

    address escrow = makeAddr("escrow");
    address adapter = makeAddr("adapter");

    function setUp() public {
        verifier = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE, address(verifier).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE);
        verifier.setValid(true);

        uint256 nonce = vm.getNonce(address(this));
        address predictedLedger = vm.computeCreateAddress(address(this), nonce + 2);

        riyaUSD = new RiyaUSD(predictedLedger);
        asc = new RiyaASC(CHAIN_KEY, escrow, adapter, predictedLedger);
        ledger = new LoanLedger(address(asc), riyaUSD);
    }

    /*//////////////////////////////////////////////////////////////
                             THE REPLAY KEY
    //////////////////////////////////////////////////////////////*/

    /// @dev Two proofs differing in height or index must never produce the same key. If they
    ///      did, one real proof would permanently block another.
    function testFuzzDistinctProofsProduceDistinctKeys(uint64 heightA, uint64 heightB, uint64 indexA, uint64 indexB)
        external
        pure
    {
        // ARRANGE
        heightA = uint64(bound(heightA, 1, type(uint64).max));
        heightB = uint64(bound(heightB, 1, type(uint64).max));
        vm.assume(heightA != heightB || indexA != indexB);

        // ACT
        bytes32 keyA = _key(heightA, indexA);
        bytes32 keyB = _key(heightB, indexB);

        // ASSERT
        assertTrue(keyA != keyB);
    }

    /// @dev The worker rebuilds this key off-chain to decide whether to skip a submission,
    ///      so it has to be a pure function of the four inputs and nothing else.
    function testFuzzTheKeyIsDeterministic(uint64 height, uint64 txIndex, bytes32 root) external pure {
        // ARRANGE
        // ACT
        bytes32 first = keccak256(abi.encode(CHAIN_KEY, height, root, txIndex));
        bytes32 second = keccak256(abi.encode(CHAIN_KEY, height, root, txIndex));

        // ASSERT
        assertEq(first, second);
    }

    /// @dev `abi.encode` pads to 32 bytes; `abi.encodePacked` does not. Getting this wrong
    ///      fails silently: `isConsumed` simply always answers no.
    function testFuzzPackedEncodingWouldProduceADifferentKey(uint64 height, uint64 txIndex, bytes32 root)
        external
        pure
    {
        // ARRANGE
        // ACT
        bytes32 padded = keccak256(abi.encode(CHAIN_KEY, height, root, txIndex));
        bytes32 packed = keccak256(abi.encodePacked(CHAIN_KEY, height, root, txIndex));

        // ASSERT
        assertTrue(padded != packed, "the two encodings are not interchangeable");
    }

    /// @dev Every unseen key reads false, and the one that was consumed reads true. Nothing
    ///      else in the mapping moves.
    function testFuzzOnlyTheSubmittedKeyBecomesConsumed(uint64 height, uint64 txIndex, uint64 otherIndex) external {
        // ARRANGE
        height = uint64(bound(height, 1, type(uint64).max));
        vm.assume(txIndex != otherIndex);

        verifier.setTxIndex(txIndex);

        // ACT
        _submit(height, _depositTx(escrow, makeAddr("alice"), 1_000e6));

        // ASSERT
        assertTrue(asc.isConsumed(_key(height, txIndex)));
        assertFalse(asc.isConsumed(_key(height, otherIndex)));
    }

    /// @dev Proof bytes are public and `submit` is permissionless, so a second submission of
    ///      the same proof must revert whoever sends it and whatever height it claims.
    function testFuzzAnyResubmissionOfTheSameProofReverts(uint64 height, uint64 txIndex, address caller) external {
        // ARRANGE
        height = uint64(bound(height, 1, type(uint64).max));
        verifier.setTxIndex(txIndex);

        bytes memory encoded = _depositTx(escrow, makeAddr("alice"), 1_000e6);
        _submit(height, encoded);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(RiyaASC.RiyaASC__AlreadyConsumed.selector, _key(height, txIndex)));
        vm.prank(caller);
        asc.submit(height, encoded, _merkleProof(), _continuityProof());
    }

    /*//////////////////////////////////////////////////////////////
                            THE EMITTER PIN
    //////////////////////////////////////////////////////////////*/

    /// @dev Event signatures are public, so anyone can emit `TokensDepositedConfirmedByEscrow`
    ///      with any amount they like. `log.address_` is the field they cannot forge.
    function testFuzzNoImpostorCanCreateCollateral(address emitter, address user, uint256 assets) external {
        // ARRANGE
        vm.assume(emitter != escrow);
        assets = bound(assets, 1, type(uint128).max);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__NoRelevantLog.selector);
        _submit(1_000, _depositTx(emitter, user, assets));

        assertEq(ledger.s_collateral(user), 0);
    }

    /// @dev The same for the harvest side, where a forged amount would retire every
    ///      borrower's debt at once.
    function testFuzzNoImpostorCanDistributeYield(address emitter, uint256 gross) external {
        // ARRANGE
        vm.assume(emitter != adapter && emitter != escrow);
        gross = bound(gross, 1, type(uint128).max);

        verifier.setTxIndex(1);
        _submit(1_000, _depositTx(escrow, makeAddr("alice"), 1_000e6));

        // ACT
        // ASSERT
        verifier.setTxIndex(2);
        vm.expectRevert(RiyaASC.RiyaASC__NoRelevantLog.selector);
        _submit(1_001, _harvestTx(emitter, makeAddr("caller"), gross));

        assertEq(ledger.s_yieldPerShare(), 0);
    }

    /// @dev A genuine deposit of any size lands verbatim. The escrow's figure becomes the
    ///      user's collateral with no scaling and no interpretation.
    function testFuzzProvenDepositLandsVerbatim(address user, uint256 assets, uint64 height) external {
        // ARRANGE
        assets = bound(assets, 1, type(uint128).max);
        height = uint64(bound(height, 1, type(uint64).max));

        // ACT
        _submit(height, _depositTx(escrow, user, assets));

        // ASSERT
        assertEq(ledger.s_collateral(user), assets);
        assertEq(ledger.s_totalCollateral(), assets);
    }

    /*//////////////////////////////////////////////////////////////
                              OTHER GUARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev A reverted source transaction still sits in a block and still proves cleanly, so
    ///      the receipt status is the only thing standing between it and the ledger.
    function testFuzzARevertedSourceTransactionNeverApplies(address user, uint256 assets) external {
        // ARRANGE
        assets = bound(assets, 1, type(uint128).max);

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmTxFixture.log(escrow, EvmTxFixture.topics3(DEPOSIT_SIG, _b32(user), bytes32(assets)));
        bytes memory encoded = EvmTxFixture.encode(0, logs);

        // ACT
        // ASSERT
        vm.expectRevert(abi.encodeWithSelector(RiyaASC.RiyaASC__TxReverted.selector, encoded));
        _submit(1_000, encoded);

        assertEq(ledger.s_collateral(user), 0);
    }

    /// @dev Whatever the proof carries, height zero is not a block.
    function testFuzzHeightZeroIsAlwaysRejected(address user, uint256 assets) external {
        // ARRANGE
        assets = bound(assets, 1, type(uint128).max);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ZeroHeight.selector);
        _submit(0, _depositTx(escrow, user, assets));
    }

    /// @dev When the precompile says no, nothing downstream runs, whatever the logs say.
    function testFuzzARejectedProofNeverReachesTheLedger(address user, uint256 assets, uint64 height) external {
        // ARRANGE
        assets = bound(assets, 1, type(uint128).max);
        height = uint64(bound(height, 1, type(uint64).max));
        verifier.setValid(false);

        // ACT
        // ASSERT
        vm.expectRevert(RiyaASC.RiyaASC__ProofInvalid.selector);
        _submit(height, _depositTx(escrow, user, assets));

        assertEq(ledger.s_collateral(user), 0);
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
