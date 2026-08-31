// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    EvmV1Decoder
} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

contract RiyaASC {
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

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RiyaASC__AlreadyConsumed(bytes32 key);
    error RiyaASC__ProofInvalid();
    error RiyaASC__TxReverted();
    error RiyaASC__NoRelevantLog();
    error RiyaASC__ZeroChainKey();
    error RiyaASC__ZeroAddress();
    error RiyaASC__ZeroHeight();

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum RiyaASCActions {
        EscrowDeposited, // 0
        AdapterHarvested // 1
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    INativeQueryVerifier public immutable I_VERIFIER;

    uint64 public immutable I_CHAIN_KEY;

    bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE =
        keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");

    bytes32 private constant ADAPTER_HARVEST_EVENT_SIGNATURE =
        keccak256("TokensHarvested(address,uint256)");

    address public immutable I_ESCROW_CONTRACT; // trusted for DEPOSIT_SIG only

    address public immutable I_ADAPTER_CONTRACT; // trusted for HARVEST_SIG only

    // LoanLedger public immutable I_LEDGER;

    mapping(bytes32 key => bool isConsumed) private s_consumed;

    /*///////////////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////////////////*/

    event TokensDepositedConfirmedByEscrow(
        address indexed user,
        uint256 indexed assets
    );
    event TokensHarvested(address indexed caller, uint256 indexed assets);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(uint64 chainKey, address escrow, address adapter) {
        // Get the precompile instance using the helper library
        I_VERIFIER = NativeQueryVerifierLib.getVerifier();

        if (chainKey == 0) revert RiyaASC__ZeroChainKey();
        if (escrow == address(0)) revert RiyaASC__ZeroAddress();
        if (adapter == address(0)) revert RiyaASC__ZeroAddress();

        I_CHAIN_KEY = chainKey;
        I_ESCROW_CONTRACT = escrow;
        I_ADAPTER_CONTRACT = adapter;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function submit(
        uint64 height,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external {
        // CHECKS
        if (height == 0) revert RiyaASC__ZeroHeight();
        // EFFECTS
        // INTERACTIONS
        uint64 txIndex = I_VERIFIER.calculateTxIndex(merkleProof);
        bytes32 key = keccak256(
            abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex)
        );
        if (s_consumed[key]) revert RiyaASC__AlreadyConsumed(key);
        s_consumed[key] = true;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _submit() internal {}

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
