// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifier} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/**
 * @title MockNativeQueryVerifier
 * @author Kelechi Kizito Ugwu
 * @notice Stands in for the Block Prover Precompile at `0x0FD2` in tests.
 * @dev The precompile is native code that exists only on Creditcoin, so a local run has
 *      nothing at that address. Tests `vm.etch` this there instead.
 *
 *      Verification is a settable flag rather than real Merkle arithmetic. `RiyaASC` treats
 *      the precompile as an oracle and only branches on its answer, so what needs testing
 *      is both answers, not the cryptography behind them.
 */
contract MockNativeQueryVerifier {
    bool public s_valid = true;
    uint64 public s_txIndex;

    event TransactionVerified(uint64 indexed chainKey, uint64 indexed height, uint64 transactionIndex);

    function setValid(bool valid) external {
        s_valid = valid;
    }

    function setTxIndex(uint64 txIndex) external {
        s_txIndex = txIndex;
    }

    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata) external view returns (uint64) {
        return s_txIndex;
    }

    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata,
        INativeQueryVerifier.MerkleProof calldata,
        INativeQueryVerifier.ContinuityProof calldata
    ) external returns (bool) {
        if (s_valid) {
            emit TransactionVerified(chainKey, height, s_txIndex);
        }
        return s_valid;
    }
}
