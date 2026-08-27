# Checkpoint 6 · `RiyaASC` — verify, then decide

> Part of the riya guided build. File to write: `src/ASC.sol`, replacing the stub.
>
> This is the contract that makes riya a Creditcoin project rather than a generic EVM
> app. Delete it and there is no product — the loan cannot learn that yield arrived.

---

## First, the stub is wrong

What is there now:

```solidity
function mintFromQuery(
    uint64 chainKey, uint64 blockHeight, bytes calldata encodedTransaction,
    bytes32 merkleRoot, INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
    bytes32 lowerEndpointDigest, bytes32[] calldata continuityRoots
) external virtual returns (bool);
```

Two problems:

1. **The name is from the bridge example.** riya mints nothing here — it credits
   collateral and retires debt.
2. **The proof parameters are flattened**, but the precompile takes structs:

```solidity
struct MerkleProofEntry { bytes32 hash; bool isLeft; }
struct MerkleProof      { bytes32 root; MerkleProofEntry[] siblings; }
struct ContinuityProof  { bytes32 lowerEndpointDigest; bytes32[] roots; }
```

---

## The shape

```solidity
contract RiyaASC {
    error RiyaASC__AlreadyConsumed(bytes32 key);
    error RiyaASC__ProofInvalid();
    error RiyaASC__TxReverted();
    error RiyaASC__NoRelevantLog();

    // TokensDepositedConfirmedByEscrow(address,uint256)
    bytes32 private constant DEPOSIT_SIG =
        0x2469ce1de96eb16d4e90a676be828ced69aa1b383d7ca7f46599a77ec4be8048;
    // TokensHarvested(address,uint256)
    bytes32 private constant HARVEST_SIG =
        0x0d0f37915a09aa89d8ce6c75bb11a6ab2c4760200de9042f0d69e86102369593;

    uint64     public immutable I_CHAIN_KEY;   // Ethereum, per Attestcoin
    address    public immutable I_ESCROW;      // trusted for DEPOSIT_SIG only
    address    public immutable I_ADAPTER;     // trusted for HARVEST_SIG only
    LoanLedger public immutable I_LEDGER;

    mapping(bytes32 => bool) private s_consumed;

    function submit(
        uint64 height,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external;
}
```

### One external function, permissionless

Anyone may submit a proof. A valid proof is a valid proof regardless of who carries it,
and gating it would mean trusting the worker's key rather than the cryptography. If your
worker dies, someone else can keep the protocol running.

### Two pins, not one

`I_ESCROW` and `I_ADAPTER` are separate immutables. That is the cost of making Ethereum
dumb: custody and strategy are different contracts, and each is trusted only for its own
event.

---

## `submit` — the logic, in order

```
1. txIndex = verifier.calculateTxIndex(merkleProof)
   key     = keccak256(abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex))
   if s_consumed[key] revert AlreadyConsumed
   s_consumed[key] = true

2. if (!verifier.verifyAndEmit(I_CHAIN_KEY, height, encodedTransaction,
                               merkleProof, continuityProof)) revert ProofInvalid

3. receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction)
   if (receipt.receiptStatus != 1) revert TxReverted

4. _dispatch(receipt)
```

`NativeQueryVerifierLib.getVerifier()` returns the precompile at `0x0FD2` — use it
rather than hardcoding the address.

### Why `verifyAndEmit` rather than `verify`

`verify` is a `view` and costs less. `verifyAndEmit` writes a `TransactionVerified`
event, giving an on-chain audit trail of every proof the protocol ever accepted. For a
hackathon submission that trail is worth more than the gas saved.

### Why the consumed flag is set before verification

Checks-effects-interactions — the precompile is an external call. It does not change
correctness here (a revert rolls the write back either way), but the habit is worth
keeping.

---

## The three checks, and the attack each stops

### 1 · Replay

Without it, one real harvest proof is submitted a thousand times and every borrower's
debt goes to zero against $35 of real yield.

The key is per-proof: chain + height + merkle root + transaction index.

A simpler alternative is `keccak256(encodedTransaction)`, unique because no transaction
appears in two blocks, and it saves a precompile call. The four-part key is more
explicit about *why* it is unique. Either is defensible.

### 2 · `receiptStatus == 1`

The precompile proves the transaction was **included**, not that it **succeeded**. A
reverted transaction still sits in a block, still has a receipt, and still gets a valid
Merkle proof.

Creditcoin's own answer (recorded in `CLAUDE.md`) confirms it:

> *"The proof can be decoded, and the status field will be 1 or 0."*

Without this check, someone calls `harvest()` in a way that reverts and proves it anyway.

### 3 · The emitter pin

The signature hash is public. Anyone can deploy a contract that emits
`TokensHarvested(address,uint256)` with a value of one billion, in a transaction that
genuinely succeeds and genuinely gets a valid proof. Every other check passes.

The only thing they cannot forge is `log.address_`.

> **Drop any one of the three and the protocol is drainable.**

---

## `_dispatch`

```
handled = false

harvests = getLogsByEventSignature(receipt, HARVEST_SIG)
for each:
    if address_ != I_ADAPTER   continue
    if topics.length < 3       continue
    I_LEDGER.onHarvest(uint256(topics[2]))
    handled = true

deposits = getLogsByEventSignature(receipt, DEPOSIT_SIG)
for each:
    if address_ != I_ESCROW    continue
    if topics.length < 3       continue
    I_LEDGER.onDeposit(address(uint160(uint256(topics[1]))), uint256(topics[2]))
    handled = true

if (!handled) revert NoRelevantLog
```

**Values come from topics, not `data`.** riya's events index everything, so `data` is
empty. This is where checkpoint 4 pays off — and it is exactly where copying
`ASCMinter`'s `abi.decode(log.data, (uint256))` would revert.

**Loops, not single reads**, because one transaction can emit the same event many times.
Today it cannot, but the loop costs nothing and removes a future assumption.

**Harvests before deposits.** They cannot currently appear in the same transaction, so it
does not bite — but if they ever did, processing the harvest first is correct: a
depositor who arrived in that same transaction was not in the pool when the yield
accrued and should not share it.

**`continue`, not `revert`, on a failed pin.** An impostor log is ignored, and any
legitimate log in the same transaction still processes. Reverting would let anyone grief
you by emitting a fake log in a transaction that also contains a real one.

**`NoRelevantLog` at the end** stops someone burning your CTC by submitting valid proofs
of unrelated transactions.

---

## Two things to resolve

### `I_CHAIN_KEY` is a value to look up, not invent

It is Attestcoin's identifier for Ethereum, and it is the same value the worker puts in
the proof-server URL:

```
proof-by-tx/{chain_key}/{tx_hash}
```

Get it from the Creditcoin docs and use one constant in both places.

### The circular dependency, again

The ASC needs the ledger's address; the ledger's `onlyASC` needs the ASC's. Same fix as
the escrow/adapter pair — `vm.computeCreateAddress` with `nonce + 1`, one script, both
`immutable`.

Also set the following in `foundry.toml` before scripting against Creditcoin testnet,
per the team's answer in `CLAUDE.md`:

```toml
bypass_prevrandao = true
```

---

## Tests (checkpoint 9)

- Same proof twice → `AlreadyConsumed`
- `receiptStatus == 0` → `TxReverted`
- `TokensHarvested` from an impostor address → ignored
- `TokensDepositedConfirmedByEscrow` emitted by the **adapter** → ignored (the pins are
  not interchangeable)
- Transaction with no relevant log → `NoRelevantLog`
- Valid harvest → `onHarvest` called with exactly `topics[2]`
- A log with only 2 topics → skipped, not reverted

All of these need a mock verifier `vm.etch`'d at `0x0FD2` and hand-built
`encodedTransaction` bytes. That fixture builder is the real work of checkpoint 9.

---

**Next:** Checkpoint 5 — the keeper and the readability worker, now that the contract
they feed exists.
