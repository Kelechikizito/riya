# Checkpoint 4 · Event design — what the ASC actually sees

> Part of the riya guided build. **No new file.** This is the checkpoint that turns
> checkpoint 6 from magic into arithmetic.

---

## An EVM log has exactly two parts

```
topics[]  →  up to 4 slots, 32 bytes each. Searchable.
data      →  arbitrary length, ABI-encoded. Not searchable.
```

`topics[0]` is always the **signature hash**, so you get 3 slots for your own use.
That is the origin of the "max 3 indexed parameters" rule — it is not arbitrary, it
is what is left over.

---

## The signature hash

Hash of the signature *string*, canonical form only:

```
keccak256("TokensHarvested(address,uint256)")
```

**In it:** the name and the parameter types.
**Not in it:** parameter names, spaces, and `indexed`.

That last one matters — marking a parameter `indexed` changes where it lands but never
changes the hash.

### riya's four, computed

| Event | `topics[0]` |
|---|---|
| `TokensDepositedConfirmedByEscrow(address,uint256)` | `0x2469ce1de96eb16d4e90a676be828ced69aa1b383d7ca7f46599a77ec4be8048` |
| `TokensHarvested(address,uint256)` | `0x0d0f37915a09aa89d8ce6c75bb11a6ab2c4760200de9042f0d69e86102369593` |
| `TokensDepositedConfirmedByAdapter(uint256,uint256)` | `0xa4c2ead58f791605b237d850e11bf6579ae4f80fc514544e022fd8ad0f96da9b` |
| `TokensWithdrawn(address,uint256,uint256)` | `0xffe903c0abe6b2dbb2f3474ef43d7a3c1fca49e5a774453423ca8e1952aabffa` |

The first two become constants in the ASC. Rename an event by one character and the
hash changes completely, the filter matches nothing, and **the ASC silently does
nothing** — no revert, no signal.

Regenerate any of these with:

```bash
cast keccak "TokensHarvested(address,uint256)"
```

---

## Where each parameter lands

| Parameter | Goes to |
|---|---|
| `indexed`, value type (`uint256`, `address`, `bool`, `bytes32`) | `topics[n]` — the value itself |
| not `indexed` | `data`, ABI-encoded |
| `indexed`, **dynamic** type (`string`, `bytes`, array, struct) | `topics[n]` — but only `keccak256(value)`. **The value is gone.** |

The last row is the real trap: you can filter by an indexed string but never read it
back. None of riya's events go near it — every parameter is a `uint256` or an
`address`.

---

## riya's two events, decoded

Both index everything, so **`data` is empty in both** and everything is read from
topics.

### Deposit

`TokensDepositedConfirmedByEscrow(address indexed user, uint256 indexed assets)`

```
topics[0] = 0x2469ce1d…         the signature hash
topics[1] = 0x…000000alice      the depositor
topics[2] = 0x…0000005f5e100    100000000  ($100)
data      = 0x                  empty
```

```solidity
address user   = address(uint160(uint256(log.topics[1])));
uint256 assets = uint256(log.topics[2]);
```

### Harvest

`TokensHarvested(address indexed caller, uint256 indexed assets)`

```
topics[0] = 0x0d0f3791…         the signature hash
topics[1] = 0x…00000keeper      whoever paid the gas — informational only
topics[2] = 0x…00000021e4dd2    35553010  ($35.55)
data      = 0x                  empty
```

```solidity
uint256 gross = uint256(log.topics[2]);
```

`topics[1]` here is the keeper's address, and the ledger does not care who it was —
yield is shared pro-rata regardless of who paid the gas.

### The address cast

```solidity
address user = address(uint160(uint256(log.topics[1])));
```

A topic is 32 bytes; an address is 20. The `uint256 → uint160 → address` chain
truncates from the **right**, which is where the address sits. Doing it in one step
will not compile, and doing it wrong gives a plausible-looking wrong address.

---

## What `EvmV1Decoder` hands you

```solidity
struct LogEntry { address address_; bytes32[] topics; bytes data; }

struct ReceiptFields {
    uint8 receiptStatus;
    uint64 receiptGasUsed;
    LogEntry[] receiptLogs;
    bytes receiptLogsBloom;
}
```

Two functions do the work:

```solidity
ReceiptFields memory r = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
LogEntry[] memory hits = EvmV1Decoder.getLogsByEventSignature(r, HARVEST_SIG);
```

`getLogsByEventSignature` filters on `topics[0]` and returns **every** match — an
array, not one entry, because a single transaction can emit the same event many times.

---

## `address_` is the security field, not a data field

Every `LogEntry` carries the address that emitted it.

> **Anyone can deploy a contract that emits a log with your exact signature hash and
> any amount they like.** The hash is public; there is nothing to forge.

What they cannot forge is *which address emitted it*. So the ASC checks:

```solidity
if (hits[i].address_ != i_adapter) continue;   // for harvests
if (hits[i].address_ != i_escrow)  continue;   // for deposits
```

Per-event, not one shared pin. `TokensHarvested` is believed only from the adapter,
`TokensDepositedConfirmedByEscrow` only from the escrow, and the two are not
interchangeable.

### Contrast with Creditcoin's own `ASCMinter`

It does the opposite — it *uses* `log.address_` as data:

```solidity
originTokenAddress = log.address_;
// …then validates it against a registry
require(wrappedTokens[originTokenAddress] != address(0), "not registered");
```

Same field, opposite roles: theirs identifies *which token*, yours proves *who spoke*.
Both are valid; know which one you are doing.

---

## Three transaction-level checks around the logs

1. **`receiptStatus == 1`.** The precompile proves *inclusion*, not success. A reverted
   transaction is still in the block, still has a receipt, and still gets a valid
   Merkle proof.
2. **Replay.** One proof, one use — keyed on chain, height, root and transaction index.
3. **Topic-count guard.** `if (log.topics.length < 3) continue;` before touching
   `topics[2]`, so a malformed log fails cleanly instead of reading out of bounds.
   `ASCMinter` does the same with `require(log.topics.length == 2)`.

---

## Why the ordering rule keeps coming back

Both events fire *after* their transfer. In a successful transaction that makes the log
and the money inseparable:

```
transfer succeeds → emit → tx succeeds → receiptStatus == 1 → proof valid
transfer fails    → whole tx reverts   → no log exists at all
```

There is no state where the log exists and the money did not move. That is why the ASC
can trust a number about a chain it cannot see.

---

## What the worker needs from all this

- Filter Ethereum logs by `topics[0]` — the two hashes above
- Filter by contract address — the escrow and the adapter
- Fetch the whole **transaction**, not the log: proofs are per-transaction, and both
  deposit logs land in one
- Submit in source-chain order — a deposit proven *after* a harvest earns no share of
  that harvest

---

**Next:** Checkpoint 5 — the keeper and the readability worker.
