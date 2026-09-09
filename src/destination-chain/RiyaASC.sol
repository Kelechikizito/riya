// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {ILoanLedger} from "src/interfaces/ILoanLedger.sol";

/**
 * @title RiyaASC
 * @author Kelechi Kizito Ugwu
 * @notice riya's Attested Smart Contract: the only door between Ethereum and Creditcoin.
 *         Takes a proof that an Ethereum transaction happened, checks it against the Block
 *         Prover Precompile, and turns the events inside it into ledger updates.
 * @dev The precompile answers one question only: is this transaction in a block that is
 *      really part of the confirmed source chain? It does not say the transaction
 *      succeeded, that you have not already acted on it, or who emitted the logs. Those
 *      three are this contract's job, and dropping any one makes the protocol drainable:
 *
 *      - Replay: proof bytes are public and `submit` is permissionless, so one real
 *        harvest could be replayed until every borrower's debt hit zero.
 *      - `receiptStatus`: a reverted transaction still sits in a block and proves cleanly.
 *      - The emitter pin: anyone can deploy a contract emitting `TokensHarvested` with a
 *        value of one billion. `log.address_` is the field they cannot forge.
 */
contract RiyaASC {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error RiyaASC__AlreadyConsumed(bytes32 key);
    error RiyaASC__ProofInvalid();
    error RiyaASC__TxReverted(bytes failedTransaction);
    error RiyaASC__NoRelevantLog();
    error RiyaASC__ZeroChainKey();
    error RiyaASC__ZeroAddress();
    error RiyaASC__ZeroHeight();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Which source-chain event a consumed proof carried.
    enum RiyaASCActions {
        EscrowDeposited, // 0
        AdapterHarvested // 1
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev The Block Prover Precompile. Constant hardcoded `0x0FD2`
    INativeQueryVerifier public immutable I_VERIFIER;

    /// @dev This Creditcoin network's registry index, not an EVM chain id and not global.
    ///      Creditcoin Testnet registers Sepolia as 1 and Ethereum Mainnet as 3.
    uint64 public immutable I_CHAIN_KEY;

    /// @dev topic0 of `RiyaEscrow`'s deposit event. Hashed from the string rather than
    ///      written as a hex literal, so it can be checked by eye: one wrong nibble in hex
    ///      compiles, deploys, and then silently matches no log ever. These two strings are
    ///      the tie to the source chain, and must change whenever those events do.
    bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE =
        keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");

    /// @dev topic0 of `AaveV4Adapter`'s harvest event.
    bytes32 private constant ADAPTER_HARVEST_EVENT_SIGNATURE = keccak256("TokensHarvested(address,uint256)");

    /// @dev `RiyaEscrow` on the source chain. Trusted for the deposit signature only.
    address public immutable I_ESCROW_CONTRACT;

    /// @dev `AaveV4Adapter` on the source chain. Trusted for the harvest signature only.
    address public immutable I_ADAPTER_CONTRACT;

    /// @dev Where every decision in the system actually lives.
    ILoanLedger public immutable I_LEDGER;

    /// @dev Spent proofs, keyed by the transaction they identify.
    mapping(bytes32 key => bool isConsumed) private s_consumed;

    /// @dev Signature plus two indexed parameters. A log with fewer shares topic0 but not
    ///      the shape, and reading `topics[2]` on it reverts.
    uint256 private constant MIN_TOPICS = 3;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The Creditcoin-side receipt for an accepted proof.
    /// @dev Keyed the same way as the replay mapping, so the audit trail and the guard
    ///      cannot disagree about what was consumed.
    /// @param key The replay key of the source-chain transaction.
    /// @param action Which event was found inside it.
    /// @param value Assets deposited, or gross yield harvested.
    event ProofConsumed(bytes32 indexed key, RiyaASCActions indexed action, uint256 value);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param chainKey This Creditcoin network's registry index for the source chain.
     * @param escrow `RiyaEscrow`'s address on that source chain.
     * @param adapter `AaveV4Adapter`'s address on that source chain.
     * @param ledger The `LoanLedger` this ASC dispatches into.
     * @dev The zero checks catch a forgotten argument, which otherwise deploys, verifies,
     *      and then rejects every proof forever. They cannot tell a wrong chain key from a
     *      right one; only the deploy script can, and it does.
     *
     *      `ledger` is circular with the ledger's own pin, so both come from one script
     *      using `vm.computeCreateAddress`.
     */
    constructor(uint64 chainKey, address escrow, address adapter, address ledger) {
        if (chainKey == 0) revert RiyaASC__ZeroChainKey();
        if (escrow == address(0)) revert RiyaASC__ZeroAddress();
        if (adapter == address(0)) revert RiyaASC__ZeroAddress();
        if (ledger == address(0)) revert RiyaASC__ZeroAddress();

        // Get the precompile instance using the helper library
        I_VERIFIER = NativeQueryVerifierLib.getVerifier();

        I_CHAIN_KEY = chainKey;
        I_ESCROW_CONTRACT = escrow;
        I_ADAPTER_CONTRACT = adapter;
        I_LEDGER = ILoanLedger(ledger);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies a source-chain transaction and applies the riya events inside it.
     * @param height The source-chain block holding the transaction.
     * @param encodedTransaction The transaction and its receipt, as the Proof Builder
     *        encoded them.
     * @param merkleProof Inclusion of the transaction in that block.
     * @param continuityProof The block's link back to an attested endpoint.
     * @dev Permissionless on purpose: a valid proof is valid whoever carries it, and
     *      gating it would mean trusting the worker's key rather than the cryptography.
     *
     *      The replay key is written before the proof is checked, which is safe for one
     *      reason only: step 2 reverts. A non-reverting failure path would leave a poisoned
     *      key behind, permanently blocking the real proof with no recovery.
     */
    function submit(
        uint64 height,
        bytes calldata encodedTransaction, // question: why not bytes32?
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external {
        // CHECKS

        // STEP 0
        if (height == 0) revert RiyaASC__ZeroHeight();

        // STEP 1: Replay protection
        // Chain + height + root + index names a transaction uniquely, in both directions.
        uint64 txIndex = I_VERIFIER.calculateTxIndex(merkleProof);
        bytes32 key = keccak256(abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex));
        if (s_consumed[key]) revert RiyaASC__AlreadyConsumed(key);
        s_consumed[key] = true;

        // STEP 2: Precompile verification
        // `verifyAndEmit` over `verify` costs a little gas and buys a `TransactionVerified`
        // log written by the precompile itself, which this contract could not have faked.
        if (!I_VERIFIER.verifyAndEmit(I_CHAIN_KEY, height, encodedTransaction, merkleProof, continuityProof)) {
            revert RiyaASC__ProofInvalid();
        }

        // STEP 3: The transaction in that block must not have reverted.
        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) {
            revert RiyaASC__TxReverted(encodedTransaction);
        }

        /// STEP 4: Dispatch
        _dispatch(key, receipt);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Turns the verified logs into ledger updates.
     * @param key The replay key, carried through only so `ProofConsumed` can quote it.
     * @param receipt The decoded receipt of a transaction already proven to have succeeded.
     * @dev Every parameter of both riya events is `indexed`, so `data` is empty and the
     *      layout is `topics = [signature, param1, param2]`. Values come out of `topics`,
     *      never `abi.decode(log.data, ...)`, which would revert on an empty byte string.
     *
     *      Harvests run before deposits, which only matters for a single transaction
     *      carrying both. There the depositor arrived after the yield accrued and should
     *      not share it, and paying the harvest out first is what excludes them.
     */
    function _dispatch(bytes32 key, EvmV1Decoder.ReceiptFields memory receipt) internal {
        bool handled;

        // Loops rather than single reads: one transaction may emit the same event many
        // times. `getLogsByEventSignature` filters on topics[0] alone, so an impostor's
        // log lands in this array too, and the `address_` pin below is what excludes it.
        EvmV1Decoder.LogEntry[] memory harvestsLogs =
            EvmV1Decoder.getLogsByEventSignature(receipt, ADAPTER_HARVEST_EVENT_SIGNATURE);

        for (uint256 i; i < harvestsLogs.length; ++i) {
            if (harvestsLogs[i].address_ != I_ADAPTER_CONTRACT) continue;

            // Skip rather than revert on both filters. Reverting would let an attacker
            // block a real proof by planting a fake log beside it in the same transaction.
            if (harvestsLogs[i].topics.length < MIN_TOPICS) continue;

            // `topics[1]` is the caller and goes unread: `harvest()` is permissionless, so
            // it is whoever poked it, with no claim on the yield. The deposit loop below
            // does read it, because there it is the depositor.
            uint256 gross = uint256(harvestsLogs[i].topics[2]);
            I_LEDGER.onHarvest(gross);
            handled = true;

            emit ProofConsumed(key, RiyaASCActions.AdapterHarvested, gross);
        }

        EvmV1Decoder.LogEntry[] memory depositsLogs =
            EvmV1Decoder.getLogsByEventSignature(receipt, ESCROW_DEPOSIT_EVENT_SIGNATURE);

        for (uint256 i; i < depositsLogs.length; ++i) {
            if (depositsLogs[i].address_ != I_ESCROW_CONTRACT) continue;
            if (depositsLogs[i].topics.length < MIN_TOPICS) continue;

            address user = address(uint160(uint256(depositsLogs[i].topics[1])));
            uint256 assets = uint256(depositsLogs[i].topics[2]);
            I_LEDGER.onDeposit(user, assets);
            handled = true;

            emit ProofConsumed(key, RiyaASCActions.EscrowDeposited, assets);
        }

        // `continue` above, `revert` here. A transaction with nothing relevant in it
        // should never have been submitted: failing loudly stops someone burning CTC on
        // unrelated proofs, and says immediately that the worker is watching the wrong
        // contract.
        if (!handled) revert RiyaASC__NoRelevantLog();
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether a given replay key has already been acted on.
    /// @dev Lets the worker skip a resubmission instead of discovering it in a revert. It
    ///      rebuilds the key the same way `submit` does, in `offchain/src/worker.ts`.
    function isConsumed(bytes32 key) external view returns (bool) {
        return s_consumed[key];
    }
}
