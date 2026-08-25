# Checkpoint 2 · `IYieldAdapter` — the seam

> Part of the riya guided build. File to create:
> `src/interfaces/IYieldAdapter.sol`.
>
> Shortest file in the project. Also the one that carries the entire
> multi-strategy roadmap claim, so it is worth doing deliberately rather than as
> an afterthought.

Before the interface itself — two things about the refactored adapter's events
that decide how checkpoint 6 is written. The first is a rule for reading logs;
the second is a real hazard.

---

## Note 1: `indexed` decides *where* the ASC reads, not *whether* it can

> **Correction.** An earlier draft of this page called `uint256 indexed assets` a
> bug that would break every harvest proof. That was wrong, and the events as
> written are fine. Creditcoin's own guidance to index is sound. The reasoning
> below is the corrected version.

```solidity
event TokensHarvested(address indexed caller, uint256 indexed assets);
```

### What `indexed` actually does

An EVM log has two parts:

```
topics[]  →  up to 4 slots of 32 bytes. Searchable. topics[0] = the signature hash.
data      →  unlimited ABI-encoded blob. NOT searchable.
```

`indexed` moves a parameter **out of `data` and into `topics`**. So as written:

```
TokensHarvested(alice, 200)
  topics[0] = keccak256("TokensHarvested(address,uint256)")
  topics[1] = alice
  topics[2] = 200          ← the value itself, not a hash
  data      = 0x           ← empty, and that is fine
```

The value is not lost. `EvmV1Decoder` hands the ASC the whole log —

```solidity
struct LogEntry { address address_; bytes32[] topics; bytes data; }
```

— so at checkpoint 6 the ASC reads the amount as:

```solidity
uint256 gross = uint256(harvests[i].topics[2]);   // not abi.decode(.., data)
```

That is *simpler* than decoding `data`, not harder. The rule is that the reader
matches the event, never the other way round.

### The one case where indexing really does destroy the value

| Indexed parameter type | What lands in the topic |
|---|---|
| `uint256`, `address`, `bool`, `bytes32` — **value types** | the value, fully recoverable |
| `string`, `bytes`, arrays, structs — **dynamic types** | `keccak256(value)`. The value is **gone** |

This is the trap worth remembering, and none of the three events go near it —
every parameter in play is a `uint256` or an `address`.

### What the three events cost

| Event | Topics used | Note |
|---|---|---|
| `TokensDeposited(uint256 indexed, uint256 indexed)` | 3 of 4 | `data` empty; both values read from topics |
| `TokensWithdrawn(address indexed, uint256 indexed, uint256 indexed)` | 4 of 4 | at the legal ceiling — a fourth parameter would force un-indexing one |
| `TokensHarvested(address indexed, uint256 indexed)` | 3 of 4 | the one the ASC proves |

Gas is close to a wash and not worth optimising: an indexed word costs 375 (the
`LOG` per-topic charge), an unindexed one 256 (8 gas × 32 bytes) — about 119 gas
more per parameter.

The only live constraint is the ceiling: 3 indexed parameters maximum on a
non-anonymous event, because `topics[0]` is spent on the signature hash.
`TokensWithdrawn` is already there.

---

## ⚠️ Note 2: the event was renamed, and the ASC pins on the name

`Harvested` → `TokensHarvested`. Fine in itself, but the ASC identifies logs by
hashing the **exact signature string**:

```
keccak256("TokensHarvested(address,uint256)")   ← must match byte-for-byte
```

One character off and the log is silently skipped — not an error, just nothing
happens. Note the types matter too: `(address,uint256)`, no spaces, no parameter
names.

`indexed` is *not* part of that string, which is why note 1 is free of this
concern — indexing a parameter never changes the hash. The name and the types do.

`research/build-plan.md` has been updated to `TokensHarvested` throughout (step 0 now
records the final names). **Stop renaming it from here** — it is about to be
baked into a constant on another chain.

---

## The interface

`src/interfaces/IYieldAdapter.sol`

```solidity
interface IYieldAdapter {
    function deposit(uint256 amount) external returns (uint256 assets);
    function withdraw(uint256 amount, address to) external returns (uint256 assets);
    function harvest() external returns (uint256 assets);
    function totalAssets() external view returns (uint256);
    function yieldAccrued() external view returns (uint256);
}
```

The adapter's public surface, minus the constructor and the storage getters.

---

## Why the escrow holds this and never `AaveV4Adapter`

There is a weak version of this argument and a strong one. Know which you are
making.

### The weak claim — "so we can swap strategies"

Careful. `i_adapter` will be **immutable** in the escrow (checkpoint 3), so you
*cannot* hot-swap. Making it mutable would need an owner with a setter, and an
owner who can redirect where the money goes is a rug vector. Don't.

### The strong claims, which are real

1. **The escrow's bytecode contains no Aave.** It imports one interface with five
   functions. Read the escrow cold and there is nothing to check about Aave,
   because it cannot reach it. Smaller audit surface, smaller attack surface.
2. **A future Morpho adapter is a drop-in.** You redeploy the escrow, but you do
   not *rewrite* it. "Multi-strategy" means the escrow source is already
   strategy-agnostic — a concrete claim, not a slide.
3. **It is what makes checkpoint 9 possible.** You can test the escrow against a
   20-line `MockYieldAdapter` instead of standing up a fake Aave. This is the
   value you will actually feel this week.

---

## Why `harvest()` is in here, even though the escrow never calls it

Genuinely odd on first look. The escrow calls `deposit`. The **keeper** calls
`harvest`, off-chain, from Node.

It belongs because this interface is not only a contract with the escrow — **it
is the contract with the keeper too.** The keeper is written against this ABI.
Any future adapter must be harvestable or the keeper breaks. Putting it here says
"harvestable is part of what a yield adapter *is*."

Same reasoning for the two views: the keeper polls `yieldAccrued()` on a loop. If
a replacement adapter did not expose it, your off-chain code stops working.

---

## Why there is no `principal()`

It existed in an earlier draft to feed a share price. Nothing computes a share
price any more — collateral is 1:1 with escrowed dollars, on Creditcoin.

`s_principal` stays `public` on the adapter (free getter, useful when debugging)
but it is **not part of the abstraction.** A future adapter might measure
principal completely differently, or not at all.

> An interface should say *what a thing can do*, not *what it stores*.

---

## Should the events go in the interface?

Yes — with a caveat worth knowing: **Solidity does not enforce it.** Declaring an
event in an interface does not make an implementer emit it. It is documentation,
not a compiler check.

Include them anyway, because the event signature is now a cross-chain dependency
— a constant hardcoded on Creditcoin. Having one file that says "any yield
adapter MUST emit `TokensHarvested(address,uint256)`" is where you would look
before writing a second adapter. It does not stop you being wrong; it stops you
being wrong *by accident*.

---

## Two changes this implies elsewhere

### 1. Make the adapter declare it

```solidity
contract AaveV4Adapter is IYieldAdapter, ReentrancyGuard {
```

**This is the change that does actual work.** Without it, the interface is a file
nobody checks. Once the adapter inherits it, the compiler errors if any signature
drifts apart.

Two Solidity details that make this painless:

- Since **0.8.8** you do not need `override` on interface implementations.
- A `public` function satisfies an `external` interface function — so
  `totalAssets()` and `yieldAccrued()` stay `public`, untouched.

### 2. The `// @to-do: write the vault interface for later` — you don't need it

On `I_ESCROW = vault;`. Skip it. The test for why:

> **An interface is for calling something. `address` is for identifying
> something.**

The adapter never *calls* the vault. It does exactly two things with that
address:

```solidity
if (msg.sender != I_ESCROW) revert ...;      // comparison
I_ASSET.safeTransfer(I_ESCROW, assets);      // destination
```

Neither needs to know the vault has functions. Typing it as `IVault` would
advertise a capability that does not exist, and would make the two contracts
import each other — escrow imports `IYieldAdapter`, adapter imports `IVault` — a
circular conceptual dependency for zero benefit.

The arrow points **one way**: escrow → adapter. Keep it that way.

(`research/build-plan.md` step 8 mentions an `IVault` for scripts; scripts can use the
concrete type.)

---

## One decision to make

The escrow needs to know which token to approve. Two options:

- **A.** Escrow takes `asset` in its constructor.
- **B.** Escrow reads it from the adapter: `i_asset = i_adapter.asset()`.

**B is better**, for the reason you already met at checkpoint 1 — derive what you
can derive, so there is no second field to get wrong. With A, someone deploys an
escrow holding USDC pointed at a DAI adapter, and nothing complains until the
first deposit.

B costs a sixth signature:

```solidity
function asset() external view returns (address);
```

One wrinkle: `public immutable I_ASSET` auto-generates a getter called
`I_ASSET()`, which does not match `asset()`. Cleanest fix is a one-line explicit
getter on the adapter returning `I_ASSET`.

---

## How to verify this checkpoint

There are no tests for an interface. The verification *is* the compiler:

1. Write `IYieldAdapter.sol`.
2. Add `is IYieldAdapter` to `AaveV4Adapter`.
3. `forge build` — green means every signature matches. Red tells you exactly
   which one drifted.

That is the whole point of step 2. An interface nothing inherits is a comment.

---

**Next:** Checkpoint 3 — `RiyaEscrow`, custody only, and why it is deliberately
not ERC-4626.
