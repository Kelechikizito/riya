// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    EvmV1Decoder
} from "@gluwa/usc-contracts/contracts/write-ability/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/usc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {ILoanLedger} from "src/interfaces/ILoanLedger.sol";

/**
 * @title RiyaASC
 * @author Kelechi Kizito Ugwu
 * @notice riya's Attested Smart Contract: the only door between Ethereum and Creditcoin.
 *         It takes a proof that a specific Ethereum transaction happened, checks it
 *         against the Block Prover Precompile, and turns the events inside it into
 *         collateral and debt relief on `LoanLedger`.
 * @dev The shape of the system it sits in:
 *
 *      1. An off-chain worker watches `RiyaEscrow` and `AaveV4Adapter` on Ethereum.
 *      2. It waits for the block carrying the event to be attested on Creditcoin.
 *      3. It builds Merkle and continuity proofs with the Proof Builder service.
 *      4. It calls `submit` here with those proofs and the encoded transaction.
 *      5. `submit` verifies synchronously against the precompile at `0x0FD2` and
 *         dispatches into the ledger in the same transaction.
 *
 *      The precompile answers exactly one question — "is this transaction in a block
 *      that is really part of the confirmed source chain?" — and nothing more. It does
 *      not say the transaction succeeded, it does not say you have not already acted on
 *      it, and it does not say who emitted the logs inside it. Those three are this
 *      contract's job, and dropping any one of them makes the protocol drainable:
 *
 *      - **Replay** — proof bytes are public and `submit` is permissionless, so one real
 *        harvest could be replayed until every borrower's debt hit zero.
 *      - **`receiptStatus`** — a reverted transaction still sits in a block and still
 *        proves cleanly.
 *      - **The emitter pin** — event signatures are public, so anyone can deploy a
 *        contract that emits `TokensHarvested` with a value of one billion. `log.address_`
 *        is the one field they cannot forge.
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

    /// @dev Attestcoin's index into the attested-chain registry of *this* Creditcoin
    ///      network — not an EVM chain id, and not global. Creditcoin Testnet registers
    ///      Sepolia as `1` and Ethereum Mainnet as `3`.
    uint64 public immutable I_CHAIN_KEY;

    /// @dev topic0 of `RiyaEscrow`'s deposit event. Written as the hashed string rather
    ///      than a hex literal so it can be checked against the source contract by eye —
    ///      one wrong nibble in the hex version compiles, deploys, and then silently
    ///      matches no log ever.
    /// @dev These two strings are the contract's tie to the source chain. Change an event
    ///      on Ethereum and the matching string here has to change with it, or every proof
    ///      of that event stops dispatching.
    bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE =
        keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");

    /// @dev topic0 of `AaveV4Adapter`'s harvest event.
    bytes32 private constant ADAPTER_HARVEST_EVENT_SIGNATURE =
        keccak256("TokensHarvested(address,uint256)");

    /// @dev `RiyaEscrow` on the source chain. Trusted for the deposit signature only.
    address public immutable I_ESCROW_CONTRACT;

    /// @dev `AaveV4Adapter` on the source chain. Trusted for the harvest signature only.
    address public immutable I_ADAPTER_CONTRACT;

    /// @dev Where every decision in the system actually lives.
    ILoanLedger public immutable I_LEDGER;

    /// @dev The set of spent proofs, keyed by the transaction they identify. Every unseen
    ///      key reads `false` for free.
    mapping(bytes32 key => bool isConsumed) private s_consumed;

    /// @dev The minimum number of topics a riya log must carry: `topics[0]` is the event
    ///      signature, `topics[1]` and `topics[2]` the two indexed parameters. A log with
    ///      fewer shares topic0 but not the shape, and reading `topics[2]` on it reverts.
    uint256 private constant MIN_TOPICS = 3;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The Creditcoin-side receipt for an accepted proof.
    /// @dev Keyed by the same fingerprint as the replay mapping, so the audit trail and
    ///      the guard cannot disagree about what was consumed.
    /// @param key The replay key of the source-chain transaction.
    /// @param action Which event was found inside it.
    /// @param value Assets deposited, or gross yield harvested.
    event ProofConsumed(
        bytes32 indexed key,
        RiyaASCActions indexed action,
        uint256 value
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param chainKey This Creditcoin network's registry index for the source chain.
     * @param escrow `RiyaEscrow`'s address on that source chain.
     * @param adapter `AaveV4Adapter`'s address on that source chain.
     * @param ledger The `LoanLedger` this ASC dispatches into.
     * @dev The zero checks catch a forgotten constructor argument, which is the expensive
     *      kind of deploy bug: the contract deploys, verifies, and then rejects every
     *      proof forever. They do not prove the chainkey is *correct* — passing `3` where
     *      you meant `1` deploys cleanly and reads the wrong chain. Only the deploy script
     *      and a post-deploy assertion can catch that.
     *
     *      `ledger` is circular with `LoanLedger`'s own ASC pin, so both sides come from
     *      one script using `vm.computeCreateAddress`, exactly like the escrow/adapter pair.
     */
    constructor(
        uint64 chainKey,
        address escrow,
        address adapter,
        address ledger
    ) {
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
     * @dev Permissionless on purpose. A valid proof is a valid proof whoever carries it,
     *      and gating this would mean trusting the worker's key rather than the
     *      cryptography — if the worker dies, anyone can keep the protocol running.
     *
     *      No CEI banners here, because there is nothing to reenter: the precompile is
     *      native code with no fallback into this contract, and `I_LEDGER` — the one call
     *      that could — runs last. The replay key is written before the proof is checked,
     *      which is safe for one reason only: **step 2 reverts**. A non-reverting failure
     *      path would leave a poisoned key behind, permanently blocking the real proof of
     *      a real deposit with no recovery. Never soften that revert into a `return false`.
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
        // 1 · One proof, one use. Chain + height + root + index names a transaction: no two distinct transactions share all four, and the same one always produces the same four.
        uint64 txIndex = I_VERIFIER.calculateTxIndex(merkleProof); // The transaction index is simply the position of a transaction within its block — if a block holds 150 transactions, the first is index 0, the last is index 149.
        bytes32 key = keccak256(
            abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex)
        );
        if (s_consumed[key]) revert RiyaASC__AlreadyConsumed(key);
        s_consumed[key] = true;

        // STEP 2: Precompile verification
        // 2 · Did this transaction really happen on the source chain? `verifyAndEmit` over `verify` costs a little gas and buys a `TransactionVerified` log written by the precompile itself — an audit trail this contract could not have faked.
        if (
            !I_VERIFIER.verifyAndEmit(
                I_CHAIN_KEY,
                height,
                encodedTransaction,
                merkleProof,
                continuityProof
            )
        ) {
            revert RiyaASC__ProofInvalid();
        }

        // STEP 3: Success check
        // This step checks the transaction in the block didn't revert using the receiptStatus
        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder
            .decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1)
            revert RiyaASC__TxReverted(encodedTransaction);

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
     *      layout is `topics = [signature, param1, param2]`. Values are read out of
     *      `topics`, never with `abi.decode(log.data, ...)` — that would revert on an
     *      empty byte string.
     *
     *      Harvests are processed before deposits. The ordering is within a single
     *      transaction, not across time — deposits made in earlier transactions are
     *      already credited, so the question only arises for one transaction carrying
     *      both. There the depositor arrived after the yield had accrued and should not
     *      share it, so paying the harvest out first is exactly what excludes them.
     */
    function _dispatch(
        bytes32 key,
        EvmV1Decoder.ReceiptFields memory receipt
    ) internal {
        bool handled;

        // Loops rather than single reads: one transaction may emit the same event many times.
        // `getLogsByEventSignature` filters only on topics[0], so an attacker's contract
        // emitting `TokensHarvested(address,uint256)` lands in this array too. The
        // `address_` pin below is the only thing that excludes it.
        EvmV1Decoder.LogEntry[] memory harvestsLogs = EvmV1Decoder
            .getLogsByEventSignature(receipt, ADAPTER_HARVEST_EVENT_SIGNATURE);

        for (uint256 i; i < harvestsLogs.length; ++i) {
            // This line protects the ASC contract from identical logs from any contract except the adapter contract.
            if (harvestsLogs[i].address_ != I_ADAPTER_CONTRACT) continue;

            // if this log doesn't have 3 topics, like my event — skip it instead of crashing on it.
            // Reading `topics[2]` on a less than-3-topic log reverts.
            // Why continue and not revert: if it reverted, an attacker could stick a fake log next to your real harvest in the same transaction and permanently block that real proof from ever being processed. Skipping lets the real one through.
            if (harvestsLogs[i].topics.length < MIN_TOPICS) continue;

            // `topics[1]` holds the caller, and is deliberately unread. `harvest()` is
            // permissionless, so that address is whoever poked it on Ethereum — an
            // arbitrary party with no claim on the yield. `onHarvest` splits `gross`
            // pro-rata across open positions, so the caller's identity goes unused. The
            // deposit loop below does read `topics[1]`, because there it is the
            // depositor, who does have a claim.
            uint256 gross = uint256(harvestsLogs[i].topics[2]);
            I_LEDGER.onHarvest(gross);
            handled = true;

            emit ProofConsumed(key, RiyaASCActions.AdapterHarvested, gross);
        }

        EvmV1Decoder.LogEntry[] memory depositsLogs = EvmV1Decoder
            .getLogsByEventSignature(receipt, ESCROW_DEPOSIT_EVENT_SIGNATURE);

        for (uint256 i; i < depositsLogs.length; ++i) {
            if (depositsLogs[i].address_ != I_ESCROW_CONTRACT) continue;
            if (depositsLogs[i].topics.length < MIN_TOPICS) continue;

            address user = address(uint160(uint256(depositsLogs[i].topics[1])));
            uint256 assets = uint256(depositsLogs[i].topics[2]);
            I_LEDGER.onDeposit(user, assets);
            handled = true;

            emit ProofConsumed(key, RiyaASCActions.EscrowDeposited, assets);
        }

        // `continue` above, `revert` here. Skipping an impostor log lets a legitimate log
        // in the same transaction still process — reverting on the impostor would let
        // anyone grief the protocol by emitting a fake log alongside a real one. But a
        // transaction with *nothing* relevant in it should never have been submitted:
        // failing loudly stops someone burning CTC on unrelated proofs, and tells you
        // immediately when the worker is watching the wrong contract.
        if (!handled) revert RiyaASC__NoRelevantLog();
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether a given replay key has already been acted on.
    /// @dev Lets the worker skip a resubmission instead of discovering it in a revert.
    function isConsumed(bytes32 key) external view returns (bool) {
        return s_consumed[key];
    }
}
