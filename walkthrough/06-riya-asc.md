# Checkpoint 6 · `RiyaASC` — verify, then decide

> Part of the riya guided build. File: `src/RiyaASC.sol`.
>
> This is the contract that makes riya a Creditcoin project rather than a generic EVM
> app. Delete it and there is no product — the loan cannot learn that a deposit landed
> or that yield arrived.

---

## Where the contract stands

The stub is gone. `mintFromQuery` — the flattened-parameter signature copied from the
bridge example — has been replaced by `submit`, which takes the precompile's own structs:

```solidity
struct MerkleProofEntry { bytes32 hash; bool isLeft; }
struct MerkleProof      { bytes32 root; MerkleProofEntry[] siblings; }
struct ContinuityProof  { bytes32 lowerEndpointDigest; bytes32[] roots; }
```

Three of the four stub problems are now closed: the name, the parameter shape, and the
`chainKey` sourcing (see below — this one turned out to matter more than expected). What
is left to write is the body of `submit` from step 2 onward, and the ledger it dispatches
into.

**Done:** errors, event-signature constants, immutables, constructor, replay key.
**Not done:** `verifyAndEmit`, the `receiptStatus` check, `_dispatch`, `I_LEDGER`.

---

## The state, line by line

### `INativeQueryVerifier public immutable VERIFIER`

```solidity
VERIFIER = NativeQueryVerifierLib.getVerifier();
```

`getVerifier()` is `internal pure` and returns a hardcoded `0x…0FD2`. Nothing is being
looked up at deploy time — the address was known at compile time. So what does storing it
buy?

- **Gas: nothing either way.** Immutables are spliced into the deployed bytecode, exactly
  like the constant the library would have inlined. There is no SLOAD in either version.
- **A public getter, free.** `riyaAsc.VERIFIER()` lets a test, a script, or a judge
  confirm the contract really is pointed at the precompile without reading bytecode.
- **One call site instead of many.** `VERIFIER.verifyAndEmit(...)` reads better than
  `NativeQueryVerifierLib.getVerifier().verifyAndEmit(...)` at every use.

Why `immutable` and not `constant`: a `constant` initialiser must be a compile-time
literal, and a function call — even a `pure` one — is not accepted there. Writing
`constant` would mean pasting the raw address and dropping the library. `immutable` is
the version that keeps the library as the single source of truth for `0x0FD2`.

The one thing it costs is honesty of signalling: `immutable` reads as "configurable per
deployment", and this is not. A comment saying *"the precompile; constant in practice,
immutable only so the library can supply it"* removes that ambiguity.

**Naming:** every other immutable here carries the `I_` prefix. `VERIFIER` should be
`I_VERIFIER` to match.

### `uint64 public immutable I_CHAIN_KEY`

The `@question: what's the point of this variable` is answered — and the answer is that
it is load-bearing **today**, on the demo chain, not defensively for some future
multi-chain world.

Attestcoin's chainkey indexes the attested-chain registry *of the Creditcoin network the
ASC sits on*. It is not an EVM chain ID and it is not global:

| Creditcoin network | Source chain | Chainkey |
|---|---|---|
| Creditcoin Testnet (`102031`) | Ethereum Sepolia | `1` |
| Creditcoin Testnet (`102031`) | Ethereum Mainnet | `3` |
| Creditcoin Mainnet (`102030`) | Ethereum Mainnet | `1` |

Creditcoin Testnet — where the demo runs — has **two** registered source chains. An ASC
that let the caller choose the chainkey would accept an Ethereum Mainnet proof when it
wanted a Sepolia one. And "but the escrow address is pinned" does not save you: the same
address can exist on both chains, from the same deployer at the same nonce or from
CREATE2.

**The current design closes this structurally, which is better than checking it.**
`submit` has no `chainKey` parameter at all — it reads `I_CHAIN_KEY` from the immutable.
There is no untrusted input to validate because there is no input. The stub's
`mintFromQuery(uint64 chainKey, ...)` had to be defended; this cannot be attacked.

Note that `I_CHAIN_KEY` is `1` in both intended deploys, for two different reasons.
Do not let that coincidence harden into a constant.

### `RiyaASC__ZeroChainKey` and `RiyaASC__ZeroAddress`

`0` appears in neither registry, so a zero chainkey means somebody forgot a constructor
argument. Same for the two addresses. These are deploy-time footguns, and a deploy script
that silently produces a permanently-broken immutable is the expensive kind of bug — the
contract deploys, verifies, and then rejects every proof forever.

Worth noting what these checks are *not*: they do not prove the chainkey is **correct**,
only that it is not zero. Passing `3` on Creditcoin Testnet when you meant `1` deploys
cleanly and then reads the wrong chain. The constructor cannot catch that; the deploy
script and a post-deploy assertion have to.

### The two signature constants

```solidity
bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE =
    keccak256("TokensDepositedConfirmedByEscrow(address,uint256)");
```

This replaces the hardcoded hex literal, and it is the right trade. The hex version is
unreadable and unauditable by eye; a single wrong nibble produces a contract that
compiles, deploys, and silently matches no logs ever. The string version is checkable
against `RiyaEscrow` by reading it.

On gas: `constant` variables are inlined at each use site as an *expression*, so strictly
speaking `keccak256` runs at every use — but solc constant-folds `keccak256` of a literal
under the optimizer, so with the optimizer on this is free. Even with it off, it is 30-ish
gas against a bug class that costs the whole demo.

**There is a stronger version available.** The contract already declares both events
locally, and since Solidity 0.8.15 an event exposes `.selector` — its topic0:

```solidity
bytes32 private constant ESCROW_DEPOSIT_EVENT_SIGNATURE =
    TokensDepositedConfirmedByEscrow.selector;
```

Now the constant is derived from a *typed declaration* rather than a hand-typed string.
Rename a parameter type and it follows; typo the declaration and the compiler is looking
at the same typo the decoder will. Worth switching to, and it gives the two local event
declarations a job.

### Which brings up the local event declarations

`RiyaASC` declares `TokensDepositedConfirmedByEscrow` and `TokensHarvested` with exactly
the shapes `RiyaEscrow` and `AaveV4Adapter` emit. Right now nothing uses them.

Two ways to resolve that, and they point in opposite directions:

1. **Use them as the source of the signature constants** (`.selector`, above) and never
   emit them. They become schema, not output.
2. **Delete them** and keep the string literals.

What to avoid is the middle: declaring them *and* emitting them from `RiyaASC`. An
indexer watching topic0 would then see the Ethereum-side event and the Creditcoin-side
event as the same event, which is precisely the distinction the whole architecture turns
on. If the ASC should emit something when it credits a user — and it should, for the demo
— give it a distinctly named event: `DepositCredited`, `HarvestCredited`.

### `enum RiyaASCActions { EscrowDeposited, AdapterHarvested }`

Declared, unused. It is a good idea looking for its use site, and the use site is the
receipt the ASC leaves behind:

```solidity
event ProofConsumed(bytes32 indexed key, RiyaASCActions indexed action, uint256 value);
```

Emitted from `_dispatch`, that gives you a Creditcoin-side audit trail keyed by the same
replay key the mapping uses — every accepted proof, what kind it was, and what it moved.
That is a genuinely useful thing to point a judge at, and it turns a dangling type
declaration into the thing that makes the demo legible.

If it does not end up with a use site by the time `_dispatch` is written, delete it.
An unused enum in a submitted contract reads as an abandoned plan.

### `mapping(bytes32 key => bool isConsumed) private s_consumed`

The named-parameter mapping syntax (Solidity ≥0.8.18) is documentation that cannot drift
out of the code. Keep it.

Semantics: a set of spent proofs. `bytes32` is the fingerprint of one specific
source-chain transaction; `bool` is "already processed". Every unseen key reads `false`
for free — nothing is stored until a key is written.

---

## `submit` — what is written, and what it means

```solidity
uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);
bytes32 key = keccak256(
    abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex)
);
if (s_consumed[key]) revert RiyaASC__AlreadyConsumed(key);
s_consumed[key] = true;
```

**The key identifies a transaction, not a proof.** Chain + block height + that block's
merkle root + the transaction's index inside the block. No two distinct source
transactions share all four, and the same transaction always produces the same four. That
is the whole requirement.

**`calculateTxIndex` is derivation, not validation.** It reconstructs the index by
reading the `isLeft` flags off the sibling path — it is `external view`, it consults no
attested state, and it will happily return an index for a proof that is complete
nonsense. So at the moment the key is computed, every input to it except `I_CHAIN_KEY` is
attacker-controlled.

That is fine, and the reason it is fine is worth being explicit about: **the write only
survives if the transaction survives**, and the transaction cannot survive without
`verifyAndEmit` returning true two lines later. An attacker who submits a fabricated
proof to poison a key gets their `s_consumed[key] = true` rolled back along with
everything else.

The corollary is a constraint on the rest of the function: step 2 must revert, never
return false or emit-and-continue. A non-reverting failure path would leave a poisoned
key behind, and a poisoned key permanently blocks the real proof of a real deposit —
locking a user's collateral out of the system with no recovery path.

**Passing `key` in the error** is worth keeping. When the worker resubmits — and it will,
that is the normal shape of a retry loop — the revert data tells you *which* proof was
the duplicate instead of just that one was.

### The CEI comment does not match the code

The `// CHECKS / // EFFECTS / // INTERACTIONS` banners are in the wrong order relative to
what follows them. As written, an interaction (`calculateTxIndex`, a staticcall to the
precompile) runs first, then the check, then the effect.

Two honest options:

- **Drop the banners.** CEI is a heuristic against reentrancy, and there is nothing to
  reenter: the precompile is native code with no fallback into your contract, and the
  only external call that could reenter is `I_LEDGER`, which comes last anyway.
- **Remove the need for the staticcall** by keying on `keccak256(encodedTransaction)`.
  A transaction appears in exactly one block, so the encoded bytes are already unique;
  this saves the precompile round-trip and makes the ordering trivially CEI-clean. The
  four-part key is more self-documenting about *why* it is unique. Both are defensible —
  but pick one deliberately rather than inheriting it.

### `if (height == 0) revert RiyaASC__Zero…`

Unfinished — this line does not compile, and the error does not exist.

Before finishing it, decide whether it earns its place. Height `0` is genesis, which has
no transactions, so no valid proof can carry it; `verifyAndEmit` rejects it anyway. The
check duplicates the cryptography, adds bytecode, and adds a test case that asserts
something the precompile already guarantees.

Recommendation: delete the line. If you keep it, name the error `RiyaASC__ZeroHeight` and
put it with the others.

---

## What still has to be written

```
2. if (!VERIFIER.verifyAndEmit(I_CHAIN_KEY, height, encodedTransaction,
                               merkleProof, continuityProof)) revert RiyaASC__ProofInvalid

3. receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction)
   if (receipt.receiptStatus != 1) revert RiyaASC__TxReverted

4. _dispatch(receipt)
```

### Why `verifyAndEmit` rather than `verify`

`verify` is a `view` and costs less. `verifyAndEmit` writes a `TransactionVerified(chainKey,
height, transactionIndex)` event, giving an on-chain audit trail of every proof the
protocol ever accepted — emitted by the precompile itself, so it is not something your
contract could have faked. For a hackathon submission that trail is worth more than the
gas saved.

### One external function, permissionless

Anyone may submit a proof. A valid proof is a valid proof regardless of who carries it,
and gating it would mean trusting the worker's key rather than the cryptography. If your
worker dies, someone else can keep the protocol running — which is a property worth
saying out loud in the submission.

The cost of permissionlessness is that the caller pays gas for work that benefits
somebody else, which is why the worker exists at all. It is not a security cost.

### Two pins, not one

`I_ESCROW_CONTRACT` and `I_ADAPTER_CONTRACT` are separate immutables, each trusted for
exactly one event signature. That is the price of making Ethereum dumb: custody and
strategy are different contracts. Crossing the pins — accepting a deposit log from the
adapter — is a distinct bug with its own test.

---

## The three checks, and the attack each stops

### 1 · Replay

Without it, one real harvest proof is submitted a thousand times and every borrower's
debt goes to zero against $35 of real yield. Proof bytes are public and sit in Creditcoin
calldata forever; `submit` is permissionless. Anyone can resubmit anyone's proof.

The precompile can only ever answer *"this transaction is in the chain"* — a fact that
stays true forever. "You have not already acted on it" is bookkeeping it cannot do for
you.

### 2 · `receiptStatus == 1`

Inclusion is not success. A reverted transaction still sits in a block, still has a
receipt, and still gets a valid Merkle proof.

Creditcoin's own answer (recorded in `CLAUDE.md`) confirms the field is there:

> *"The proof can be decoded, and the status field will be 1 or 0."*

Without this check, someone calls `harvest()` in a way that reverts and proves it anyway.

Note that a reverted transaction emits **no logs**, so `_dispatch` would find nothing and
`NoRelevantLog` would catch it as a side effect. Do not rely on that: the specific error
is what tells you the worker is proving failed transactions, and `NoRelevantLog` would
send you looking in the wrong place.

### 3 · The emitter pin

The signature hash is public. Anyone can deploy a contract that emits
`TokensHarvested(address,uint256)` with a value of one billion, in a transaction that
genuinely succeeds and genuinely gets a valid proof. Replay passes. Status passes.
Chainkey passes. The only field they cannot forge is `log.address_`.

> **Drop any one of the three and the protocol is drainable.**

---

## `_dispatch`

```
handled = false

harvests = getLogsByEventSignature(receipt, ADAPTER_HARVEST_EVENT_SIGNATURE)
for each:
    if address_ != I_ADAPTER_CONTRACT  continue
    if topics.length < 3               continue
    I_LEDGER.onHarvest(uint256(topics[2]))
    handled = true

deposits = getLogsByEventSignature(receipt, ESCROW_DEPOSIT_EVENT_SIGNATURE)
for each:
    if address_ != I_ESCROW_CONTRACT   continue
    if topics.length < 3               continue
    I_LEDGER.onDeposit(address(uint160(uint256(topics[1]))), uint256(topics[2]))
    handled = true

if (!handled) revert RiyaASC__NoRelevantLog
```

**Values come from topics, not `data`.** Both riya events index every parameter, so
`data` is empty and the layout is `topics = [sig, param1, param2]`. This is where
checkpoint 4 pays off — and it is exactly where copying `ASCMinter`'s
`abi.decode(log.data, (uint256))` would revert on an empty byte string.

**The `topics.length < 3` guard** is not paranoia about riya's own events — it is a guard
against a log that shares topic0 but not the shape, which an impostor contract can emit
freely. Reading `topics[2]` on a two-topic log reverts, and reverting is the griefing
outcome you are trying to avoid.

**Loops, not single reads**, because one transaction can emit the same event many times.
Today it cannot, but the loop costs nothing and removes a future assumption.

**Harvests before deposits.** They cannot currently appear in the same transaction, so it
does not bite — but if they ever did, processing the harvest first is correct: a
depositor who arrived in that same transaction was not in the pool when the yield accrued
and should not share it.

**`continue`, not `revert`, on a failed pin.** An impostor log is ignored and any
legitimate log in the same transaction still processes. Reverting would let anyone grief
the protocol by emitting a fake log in a transaction that also contains a real one.

**`NoRelevantLog` at the end** stops someone burning your CTC by submitting valid proofs
of unrelated transactions — and, more usefully in practice, tells you immediately when
the worker is watching the wrong contract.

---

## Two things still to resolve

### `I_LEDGER` is commented out

Uncommenting it is blocked on `LoanLedger` existing. Note the ordering consequence: the
ASC needs the ledger's address at construction, and the ledger's `onlyASC` needs the
ASC's. Same fix as the escrow/adapter pair — `vm.computeCreateAddress` with `nonce + 1`,
one script, both `immutable`.

Per the dual-auth decision, `LoanLedger` must authenticate the ASC path and the direct
user path separately from day one — `onlyASC` on `onDeposit`/`onHarvest`, and ordinary
`msg.sender` semantics on `borrow`/`repay`. Do not let a single modifier serve both.

### `foundry.toml`

Set this before scripting against Creditcoin testnet, per the team's answer in
`CLAUDE.md` (already present, noted here so the checkpoint is self-contained):

```toml
bypass_prevrandao = true
```

---

## Tests (checkpoint 9)

Constructor:

- zero chainkey → `RiyaASC__ZeroChainKey`
- zero escrow → `RiyaASC__ZeroAddress`
- zero adapter → `RiyaASC__ZeroAddress`
- `VERIFIER()` returns `0x…0FD2`

`submit`:

- same proof twice → `RiyaASC__AlreadyConsumed`, and the returned `key` matches
- proof fails verification → `RiyaASC__ProofInvalid`, **and `s_consumed[key]` is still
  false afterwards** (this is the test that proves the rollback argument above, and it is
  the one most likely to be skipped)
- `receiptStatus == 0` → `RiyaASC__TxReverted`
- `TokensHarvested` from an impostor address → ignored
- `TokensDepositedConfirmedByEscrow` emitted by the **adapter** → ignored (the pins are
  not interchangeable)
- a log with only 2 topics → skipped, not reverted
- transaction with no relevant log → `RiyaASC__NoRelevantLog`
- one transaction carrying a real log *and* an impostor log → the real one processes
- valid harvest → `onHarvest` called with exactly `topics[2]`
- valid deposit → `onDeposit` called with `topics[1]` as the user and `topics[2]` as the
  amount

All of these need a mock verifier `vm.etch`'d at `0x0FD2` and hand-built
`encodedTransaction` bytes. That fixture builder is the real work of checkpoint 9 — build
it as a helper that takes `(emitter, topics[], data, status)` and returns encoded bytes,
because every test above is one call to it with one field changed.

---

**Next:** Checkpoint 5 — the keeper and the readability worker, now that the contract
they feed exists.
