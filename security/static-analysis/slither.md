# Slither — static analysis

| | |
| --- | --- |
| Tool | Slither 0.11.5 |
| Command | `slither src/` |
| Scope | `src/` — 25 contracts, 101 detectors |
| Commit | `fefcdc6` |
| Date | 2026-09-13 |
| Result | **60 findings. 0 exploitable.** |

```
High           arbitrary-send-erc20        x1
Medium         uninitialized-local         x3
Medium         unused-return               x1
Low            reentrancy-events           x4
Low            calls-loop                  x2
Low            reentrancy-benign           x2
Informational  naming-convention          x26
Informational  assembly                   x14
Informational  solc-version                x4
Informational  missing-inheritance         x2
Informational  pragma                      x1
```

Every High, Medium and Low is triaged below. Nothing is dismissed without a reason that
can be checked against the code.

---

## High

### `arbitrary-send-erc20` — false positive

> `AaveV4Adapter._deposit(uint256)` uses arbitrary `from` in `transferFrom`:
> `I_ASSET.safeTransferFrom(I_ESCROW, address(this), amount)`
> — [`AaveV4Adapter.sol#L152`](../../src/adapters/AaveV4Adapter.sol#L152)

**Not exploitable.** The detector fires whenever the `from` argument is not literally
`msg.sender`. Here `from` is `I_ESCROW`, an `immutable` fixed at deployment, and the only
path to `_deposit` is:

```solidity
function deposit(uint256 amount) external nonReentrant onlyEscrow returns (uint256 assets)
```

```solidity
modifier onlyEscrow() {
    if (msg.sender != I_ESCROW) revert AaveV4Adapter__NotEscrow();
    _;
}
```

So `from == I_ESCROW == msg.sender` on every reachable call. The escrow is pulling funds it
already holds and has already approved, in the same transaction. Slither cannot see through
the modifier to establish the equality.

Covered by `testFuzzOnlyTheEscrowMayMovePrincipal(address,uint256)`, which asserts every
non-escrow caller reverts.

**Action: none.**

---

## Medium

### `uninitialized-local` ×3 — intentional (1) and vendored (2)

> `RiyaASC._dispatch(...).handled` is never initialized
> — [`RiyaASC.sol#L201`](../../src/destination-chain/RiyaASC.sol#L201)

`bool handled;` is meant to start `false`. It is set to `true` inside the dispatch loops,
and the function reverts with `RiyaASC__NoRelevantLog` if it is still `false` at the end.
An explicit `= false` would cost gas and change nothing.

The other two instances are in `EvmV1Decoder.getLogsByEventSignature`, which is vendored
from `@gluwa/usc-contracts` and is not riya's code.

**Action: none.**

### `unused-return` — deliberate

> `AaveV4Adapter._harvest()` ignores the return value of
> `I_SPOKE.withdraw(I_RESERVE_ID, availableYield, address(this))`
> — [`AaveV4Adapter.sol#L192`](../../src/adapters/AaveV4Adapter.sol#L192)

The call returns `(shares, assets)` and the code destructures `(, assets)`. The share count
is genuinely unwanted — `assets` is the figure that gets transferred to the escrow and the
figure the harvest event carries. The discard is explicit in the syntax.

**Action: none.**

---

## Low

### `calls-loop` ×2 — accepted, and bounded

> `RiyaASC._dispatch` makes external calls inside a loop:
> `I_LEDGER.onHarvest(gross)` and `I_LEDGER.onDeposit(user, assets)`
> — [`RiyaASC.sol#L220`](../../src/destination-chain/RiyaASC.sol#L220),
> [`#L235`](../../src/destination-chain/RiyaASC.sol#L235)

One proven transaction may legitimately carry several riya events, so the loop is required.
The usual danger — an attacker inflating the iteration count to force an out-of-gas revert —
does not apply here, because the loop body is guarded by the emitter pin:

```solidity
if (harvestsLogs[i].address_ != I_ADAPTER_CONTRACT) continue;
```

Only logs emitted by riya's own escrow and adapter reach `I_LEDGER`. An attacker can pad a
transaction with impostor logs, but each is skipped before any external call. The iteration
bound is therefore the number of *genuine* riya events in one source-chain transaction.

The `continue` rather than `revert` is itself deliberate: reverting on an unrecognised
emitter would let anyone plant a decoy beside a real event and make the real one permanently
unprovable. Demonstrated live by `make attack`.

**Action: none. Revisit if batching ever puts many harvests in one transaction.**

### `reentrancy-benign` ×2 — guarded

> `AaveV4Adapter._deposit` / `_withdraw` write `s_principal` after calling `I_SPOKE`
> — [`AaveV4Adapter.sol#L160`](../../src/adapters/AaveV4Adapter.sol#L160),
> [`#L176`](../../src/adapters/AaveV4Adapter.sol#L176)

Both are reached only through external functions carrying `nonReentrant`, and the external
callee is the Aave V4 Spoke. The write-after-call ordering is required rather than
incidental: `s_principal` records what Aave *confirmed* it received, which is only known
once `supply` returns, and `yieldAccrued()` measures against that confirmed figure. Writing
the requested amount before the call would mis-state principal whenever Aave credits
something different.

**Action: none.**

### `reentrancy-events` ×4 — cosmetic

> Events emitted after external calls in `RiyaASC.submit`, `RiyaASC._dispatch` and
> `RiyaEscrow._deposit`

No state is written after these events and no value depends on their ordering. `RiyaEscrow`
deliberately emits the amount Aave confirmed rather than the amount requested, which
requires the adapter call to have returned first.

**Action: none.**

---

## Informational

- **`naming-convention` ×26** — riya uses `s_` for storage and `I_` for immutables
  throughout, by project convention. Slither expects mixedCase. Also flags
  `IChainInfo.get_supported_chains()`, whose snake_case name is the precompile's own and
  cannot be renamed without breaking the selector.
- **`assembly` ×14** — all inside vendored `@gluwa/usc-contracts` decoders.
- **`solc-version` ×4, `pragma` ×1** — the project pins `0.8.30`; the vendored dependency
  declares a range.
- **`missing-inheritance` ×2** — `RiyaASC` does not declare `is IRiyaASC`. See the Aderyn
  report, where the same finding is raised and actioned.

---

## Reproducing

```bash
slither src/
slither src/ --json slither.json     # machine-readable
```

Findings are triaged manually rather than suppressed with `// slither-disable`, so the raw
output stays honest and this document carries the reasoning.
