// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

interface IRiyaASC {
    function submit(
        uint64 height,
        bytes calldata encodedTransaction, // question: why not bytes32?
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external;
}
