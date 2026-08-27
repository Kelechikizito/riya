// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {INativeQueryVerifier} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

abstract contract RiyaASC {
    // The block prover precompile does not validate if a transaction was successful or not.
    // It only validates if a transaction is included in a block and that block is really a part of the confirmed source chain.
    // Therefore, a dApp's ASC MUST check the "status" field of the transaction to ensure security  0x1 → ✅ Success
    //     A typical ASC follows this pattern:
    // Receives proofs and transaction data from an off-chain worker
    // Implements replay protection to prevent duplicate processing
    // Calls the Block Prover Precompile to verify proofs synchronously
    // Extracts transaction/event data from verified transaction bytes
    // Executes business logic based on the verified data

    // An off-chain worker listens for events from the source chain smart contract

    // The worker waits for the block containing the event to be attested on Creditcoin

    // The worker generates Merkle and continuity proofs using the Proof Builder service

    // The worker calls the ASC contract with proofs and encoded transaction data

    // The ASC verifies proofs synchronously using the Block Prover Precompile

    // The ASC executes business logic immediately in the same transaction. Business logic execution either takes place in the ASC itself, or in a separate dApp contract which is called by the ASC.

    bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE = keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");

    bytes32 private constant ADAPTER_HARVEST_EVENT_SIGNATURE = keccak256("TokensHarvested(address,uint256)");

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mintFromQuery(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external virtual returns (bool success);
}
