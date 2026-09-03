# Checkpoint 8 · `LoanLedger` — where every decision lives

> Part of the riya guided build. File to create: `src/LoanLedger.sol`.
>
> **This checkpoint is in progress.** The dual-auth section below is written because it
> has to be decided *before the first line of the contract*, not after. The rest is
> outlined at the bottom and not yet expanded.

---

## Two callers, two authentication models

Write this in before anything else. It costs nothing today and it cannot be added later
without redeploying the contract that holds everyone's collateral.

`LoanLedger` is reached along two paths that have nothing in common:

| Caller | Functions | Authenticated by | Trusts |
|---|---|---|---|
| `RiyaASC` | `onDeposit`, `onHarvest` | a **proof** already verified against the precompile | one address, fixed at deploy |
| A user | `borrow`, `repay` | an **ECDSA signature** over an intent | the user's key — or later, a forwarder |

The first path carries every dollar of proven cross-chain value in the system. The second
path decides how much of it someone may borrow. They are the only two ways into the
contract, and they should never share an authentication mechanism.

### Why this comes up now, before any forwarder exists

`research/gasless-borrow.md` recommends sponsored-gas borrowing — the user signs a
`borrow()` intent and the readability worker pays the CTC. That is **deferred to
checkpoint 10** and nothing here builds it.

But the deferred version is implemented by inheriting `ERC2771Context`, and
`ERC2771Context` overrides `_msgSender()` for **the entire contract**:

```solidity
function _msgSender() internal view virtual override returns (address) {
    if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
        return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
    }
    return super._msgSender();
}
```

There is no per-function granularity in it. Inherit it, write `_msgSender()` everywhere
out of habit, and the ASC path's identity check is now resolved through an external
contract instead of a plain address comparison.

**So the seam has to exist in the contract from the start**, even though nothing sits on
the other side of it yet. Retrofitting means redeploying the ledger, which means
migrating collateral. This is the cheapest moment it will ever be.

### Be accurate about the risk

`research/gasless-borrow.md` says a relayer *"could then spoof the ASC path."* Checked
against the installed code, **that overstates it**, and the overstatement is worth
correcting rather than repeating:

OpenZeppelin 5.7's `ERC2771Forwarder` validates with `ECDSA.tryRecoverCalldata` and
nothing else — no ERC-1271, no contract-signature path. To forward a call claiming
`from = i_asc`, an attacker needs a valid ECDSA signature from the ASC's address. `RiyaASC`
is a contract and has no private key. It cannot sign, so the direct spoof does not work
against the stock forwarder.

The argument for separating the paths is still strong; it is just a different argument:

1. **Trust surface, for zero benefit.** With `_msgSender()` on the ASC path, that path's
   security stops being "one address comparison" and becomes "the forwarder contract is
   correct, its EIP-712 domain is right, its nonce handling is sound, and the address we
   deployed is the one we meant." The ASC will never need a meta-transaction — it is a
   contract calling a contract. Paying that surface for a feature you cannot use is a bad
   trade at any price.

2. **The assumption is one config change from false.** The safety above rests entirely on
   the forwarder being ECDSA-only. `trustedForwarder()` is `virtual`, and a forwarder that
   supports ERC-1271 contract signatures is a normal thing to want later. The day riya
   swaps in one, a contract address becomes impersonable and the ASC path becomes
   genuinely exploitable — silently, with no code change to the ledger.

3. **The maintenance trap, which is the realest one.** In a contract inheriting
   `ERC2771Context`, a bare `msg.sender` *looks like a bug*. Linters flag it. Reviewers
   flag it. "Use `_msgSender()` for consistency" is the most natural review comment in the
   world, and applying it introduces the vulnerability. This is a human failure mode, not
   a cryptographic one, and it is the one most likely to actually happen.

Point 3 is why the fix is not just code — it is a comment loud enough to survive a
well-meaning cleanup.

### The fix

Routine, and about four lines:

```solidity
/// @dev DELIBERATELY `msg.sender`, NOT `_msgSender()`.
///      This path is reached only by `RiyaASC` calling directly, never through a
///      forwarder, and it carries every proof-verified dollar in the system. Resolving it
///      through ERC-2771 would make its security depend on the forwarder's signature
///      handling for a meta-transaction capability the ASC can never use.
///      If a linter or a reviewer asks you to "fix" this for consistency, the answer is
///      no. See walkthrough/08-loan-ledger.md.
modifier onlyASC() {
    if (msg.sender != I_ASC) revert LoanLedger__NotASC();
    _;
}
```

and on the other side:

```solidity
function borrow(uint256 amount) external {
    address user = _msgSender();   // forwarder-aware from checkpoint 10 onward
    ...
}

function repay(uint256 amount) external {
    address user = _msgSender();
    ...
}
```

Until checkpoint 10, `LoanLedger` does **not** inherit `ERC2771Context`, so `_msgSender()`
resolves through plain `Context` and returns `msg.sender`. Behaviour today is identical.
What you have bought is that checkpoint 10 becomes one inheritance line and a constructor
argument, touching neither `onDeposit` nor `onHarvest`.

> **The rule:** `msg.sender` on the proof path. `_msgSender()` on the user path. Never
> the reverse, and never both the same.

### Two smaller traps that come with the pattern

- **Calldata length.** OZ's own warning: a forwarded call arrives with 20 extra bytes
  appended. Do not write anything in `LoanLedger` that branches on `msg.data.length`.
  Nothing currently planned does — keep it that way.
- **`_msgSender()` is not free of context.** It reads calldata. Cache it in a local at
  the top of each user function rather than calling it repeatedly; it also makes the two
  paths visually distinct when reading the file.

### Tests for this section (checkpoint 9)

- `onDeposit` / `onHarvest` from any address other than the ASC → `LoanLedger__NotASC`
- `onDeposit` called with 20 bytes of address appended to the calldata, from a non-ASC
  address → still reverts. This is the test that pins the whole section; write it now and
  it keeps passing through checkpoint 10.
- `borrow` / `repay` attribute the position to `msg.sender` while no forwarder exists
- after checkpoint 10 only: a forwarded `borrow` credits the *signer*, not the relayer —
  and a forwarded `onDeposit` still reverts

---

## The rest of this checkpoint

Not yet written. Outline, in build order:

1. **State** — `s_collateral`, `s_totalCollateral`, `s_debt`, `s_repaidByYield`,
   `s_credit`, `s_protocolFees`, `s_yieldPerShare`, `s_marker`.
2. **The mirror updates** — `onDeposit` and `onHarvest`, and the 15% fee split.
3. **The accumulator** (referred to as checkpoint 8a in `01-aave-v4-adapter.md`) — the
   MasterChef `s_yieldPerShare` pattern, and why one proof can drop every borrower's debt
   at once without looping depositors.
4. **`_settle`** — where debt actually falls, where the score moves, and where surplus
   yield lands in `s_credit`.
5. **The credit score and the LTV ladder** — 10% → 50%, and why manual repayment is
   deliberately score-neutral.
6. **`borrow`** — the single place the limit is checked.
7. **The circular deploy** — three Creditcoin contracts, one nonce prediction
   (see checkpoint 7).

---

**Next:** Checkpoint 9 — the test suite, the `MockAaveSpoke`, and the proof fixture
builder that every ASC test depends on.
