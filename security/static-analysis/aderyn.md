# Aderyn — static analysis

| | |
| --- | --- |
| Tool | Aderyn 0.6.8 |
| Command | `aderyn --src src/` |
| Scope | `src/` — 88 detectors |
| Commit | `fefcdc6` |
| Date | 2026-09-13 |
| Result | **1 high (2 instances), 5 low. 0 exploitable.** |

```
Critical   0
High       1  Reentrancy: state change after external call   (2 instances)
Medium     0
Low        5  Large numeric literal
              Literal instead of constant                    (3 instances)
              Missing inheritance
              Uninitialized local variable                   (2 instances)
              Public function not used internally
```

---

## High

### Reentrancy: state change after external call — 2 instances, both false positives

#### Instance 1 — [`RiyaASC.sol#L162`](../../src/destination-chain/RiyaASC.sol#L162)

```solidity
uint64 txIndex = I_VERIFIER.calculateTxIndex(merkleProof);   // external call
bytes32 key = keccak256(abi.encode(I_CHAIN_KEY, height, merkleProof.root, txIndex));
if (s_consumed[key]) revert RiyaASC__AlreadyConsumed(key);
s_consumed[key] = true;                                      // state write
```

**Not reachable.** `I_VERIFIER` is the Block Prover Precompile at `0x0FD2`. It is native
node code, not a contract with a fallback, so it has no path back into `RiyaASC`. There is
no reentrancy to protect against.

The ordering is also deliberate and documented in the contract: the replay key is written
*before* the proof is verified, which is safe for exactly one reason — step 2 reverts. A
non-reverting failure path would leave a poisoned key behind and permanently block the real
proof of a real deposit, with no recovery. The comment in `submit` says so, and the
invariant is covered by `testFuzzOnlyTheSubmittedKeyBecomesConsumed(uint64,uint64,uint64)`
and `testFuzzAnyResubmissionOfTheSameProofReverts`.

**Action: none. Do not "fix" by moving the write after verification.**

#### Instance 2 — [`RiyaEscrow.sol#L69`](../../src/source-chain/ethereum/RiyaEscrow.sol#L69)

```solidity
I_ADAPTER = IYieldAdapter(aaveAdapterAddress);
I_ASSET = IERC20(IYieldAdapter(aaveAdapterAddress).asset());   // external call in constructor
I_MIN_DEPOSIT = minDeposit;
```

**Not reachable.** This is the constructor. The contract has no code at its address yet and
no external party can call into it, so reentrancy is not possible. The call reads
`asset()` off the adapter so the escrow cannot be deployed pointing at a token the adapter
does not actually hold — a check worth the call.

**Action: none.**

---

## Low

### Large numeric literal — [`LoanLedger.sol#L53`](../../src/destination-chain/LoanLedger.sol#L53)

```solidity
uint256 private constant BPS_DENOMINATOR = 10_000;
```

Already a named constant with digit separators. The detector flags the magnitude, not the
style. **Action: none.**

### Literal instead of constant ×3 — [`LoanLedger.sol#L295-296`](../../src/destination-chain/LoanLedger.sol#L295)

```solidity
uint256 s = (s_repaidByYield[user] * 100) / target;
return s > 100 ? 100 : s;
```

The `100`s are the score's scale — the function returns 0–100 by definition, and the name
`score` carries that meaning. Extracting `SCORE_MAX = 100` would add a constant that only
restates the return type's contract.

**Action: none. Defensible either way; noted rather than changed.**

### Missing inheritance — [`RiyaASC.sol#L29`](../../src/destination-chain/RiyaASC.sol#L29)

```solidity
contract RiyaASC {
```

`RiyaASC` implements `submit` with the signature declared in
[`IRiyaASC`](../../src/interfaces/IRiyaASC.sol) but does not declare `is IRiyaASC`. Slither
raises the same finding independently.

The interface exists so `LoanLedger` can hold the ASC by type without importing the
implementation. Declaring the inheritance would have the compiler enforce that the two stay
in step, instead of leaving it to review.

**Action: worth doing. The only real change either tool surfaced.** Low risk — it adds a
compile-time check and no runtime behaviour.

### Uninitialized local variable ×2 — [`RiyaASC.sol#L209`](../../src/destination-chain/RiyaASC.sol#L209), [`#L229`](../../src/destination-chain/RiyaASC.sol#L229)

```solidity
for (uint256 i; i < harvestsLogs.length; ++i) {
```

`uint256 i;` with no `= 0` is the standard gas-saving idiom and behaves identically.

**Action: none.**

### Public function not used internally — [`LoanLedger.sol#L278`](../../src/destination-chain/LoanLedger.sol#L278)

```solidity
function pendingYield(address user) public view returns (uint256)
```

`pendingYield` is `public` but never called from inside the contract, so `external` would be
marginally cheaper. It is left `public` deliberately: `score` and `maxLtvBps` next to it are
`public` because `borrow` does call them internally, and a mix of visibilities across three
adjacent view functions that form one read API reads as accidental.

The frontend calls it on every dashboard render
([`usePosition.ts`](../../frontend/lib/usePosition.ts)), so it is genuinely part of the
external surface.

**Action: none.**

---

## Summary

Aderyn and Slither agree on the shape of this codebase: no exploitable findings, and the
high-severity hits are both detectors that cannot see through a modifier, a precompile, or
a constructor.

The one item worth acting on is **`RiyaASC` not declaring `is IRiyaASC`**, raised by both
tools. It converts a convention into a compiler-enforced check.

## Reproducing

```bash
aderyn --src src/
aderyn --src src/ -o aderyn.json     # machine-readable
```
