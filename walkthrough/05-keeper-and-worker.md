# Checkpoint 5 · The keeper and the readability worker

> Part of the riya guided build. Files to create:
> `offchain/src/keeper.ts` and `offchain/src/worker.ts` — **two programs, not one.**
>
> The only checkpoint with no Solidity in it, and the one carrying the correctness
> property that appears in none of the contracts.
>
> Grounded in Creditcoin's *Offchain Readability Workers* documentation. Where the docs
> state something, they win over inference — and where riya deviates from the shape they
> assume, this checkpoint says so explicitly.

> **Revised after adopting [`@gluwa/usc-sdk`](https://docs.attestcoin.org/attestcoin-protocol/dapp-builder-infrastructure/attestcoin-sdk-usc-sdk).**
> The first draft of this checkpoint was written against the prose docs alone and carried
> five open unknowns. The SDK is now installed and its type definitions are the
> authority — they close three of those unknowns, correct the stack choice (**ethers v6,
> not viem**), and reveal a **second precompile at `0x0FD3`** the earlier draft did not
> know existed. Sections that changed say so in place rather than quietly reading as if
> they were always right.
>
> Note the naming: *"USC (Universal Smart Contract) was replaced with the term Attestcoin
> Protocol"* but the package is still `usc-sdk`. Same thing, older name.

---

## The question this answers

From `src/adapters/AaveV4Adapter.sol:134`, written next to `harvest()`:

> *"who calls the harvest function to trigger the event, i would assume the readability
> worker, righttt? … The job of the readability worker in CTC is to pick up events,
> c'est fini."*

**The second half is right and the first half is wrong.** The readability worker picks up
events; it does not create them. Something else has to call `harvest()`, and that
something is the keeper — a separate program, on a separate chain, paying a separate gas
token, with a separate key.

Two jobs that happen to sit next to each other in a sequence diagram are not one job.

---

## What the documentation actually says

Attestcoin's model has **two transactions** per unit of cross-chain data:

> *"The first transaction must always be submitted by the end user. However, the second
> transaction can be initiated by an off-chain worker on behalf of the user."*

And the worker exists primarily for **user experience**, not liveness:

> *"Without a worker, users would need to wait for attestation (several minutes),
> manually generate proofs, format the proof data correctly, and then submit a second
> transaction. With a worker, users only need to sign the initial source chain
> transaction."*

That is the framing to lead with in the submission. riya's user does one thing: approve
and deposit USDC on Ethereum. They never see a proof, never wait for an attestation,
never touch Creditcoin to get their collateral credited. The worker is what buys that.

Two further notes from the docs, both worth carrying:

- **The docs' code is educational.** *"not to be directly deployed in production."* Treat
  any snippet from them as a shape, not a dependency.
- **Third-party relayers are coming.** *"In the future, 3rd party relayers will offer the
  submission of readability queries as a service. A dApp team may choose to pay a small
  fee per readability query rather than maintaining their own worker."* That belongs in
  the roadmap: riya's worker is replaceable by a paid relayer, which is a credible
  operational de-risking story for Product Vision.

### Where riya deviates from the documented shape

The docs' worked example is a token bridge, where the source-chain event is always
user-initiated (`TokensBurnedForBridging`). riya has **two** proven events, and only one
of them fits that model:

| Proven event | Source-chain transaction sent by | Fits the docs' model? |
|---|---|---|
| `TokensDepositedConfirmedByEscrow` | the **user**, depositing | yes |
| `TokensHarvested` | **nobody in particular** — `harvest()` is permissionless | no |

**The keeper exists entirely because of the second row.** There is no user behind a
harvest, so there is no "first transaction the end user submits" — and the Attestcoin
documentation, quite reasonably, does not model that case. The keeper is a riya
component, not an Attestcoin one, and it should be described that way in the submission
so nobody looks for it in the protocol docs.

---

## The split

| | **Keeper** | **Readability worker** |
|---|---|---|
| Part of the Attestcoin model | no — riya-specific | **yes** — the documented component |
| Reads | Ethereum | Ethereum + Creditcoin |
| Writes | Ethereum — `adapter.harvest()` | Creditcoin — `RiyaASC.submit()` |
| Knows the other chain exists | **no** | yes |
| Gas token | ETH | tCTC |
| Trigger | `yieldAccrued() >= I_MIN_HARVEST` | a matching log appeared |
| Natural cadence | hours to days | minutes |
| Privileged? | no — `harvest()` is permissionless | no — `submit()` is permissionless |
| If it dies | yield keeps accruing in Aave; nothing breaks | Creditcoin state goes stale |
| Can you delete it? | **yes** | no |

Read the last two rows together. The keeper is *optional infrastructure* — a convenience
that saves a human from clicking a button. The worker is *the only path* by which
anything reaches Creditcoin. They do not deserve the same file, the same process, or the
same uptime budget.

### Neither one is trusted

Worth saying out loud in the submission, because it is unusual and it is free:

`harvest()` has no `onlyEscrow` modifier (checkpoint 1 explains why the earlier draft's
gating evaporated once the fee moved to Creditcoin). `submit()` is deliberately
permissionless (checkpoint 6). So **neither bot holds any authority the protocol
depends on.** If both processes die, anyone with a wallet can call `harvest()` and anyone
with proofs can call `submit()`, and the protocol continues.

That is the difference between an off-chain component that is a liveness helper and one
that is a trusted oracle. riya has only the first kind.

---

## Why two files, concretely

Tidiness is the weakest of the reasons. The real ones:

### 1. A merged bot proves only its own harvests — and that is a bug

This is the argument that settles it.

`harvest()` is permissionless. A yield farmer, a rival keeper, or a curious judge can
call it, and the yield lands in the escrow and the adapter emits `TokensHarvested`. That
harvest is exactly as real as one your keeper triggered.

A merged program written the obvious way — *call harvest, take the receipt, prove that
receipt* — never sees it. The yield sits in the escrow, backing nothing, and
`s_yieldPerShare` never rises. Every borrower's debt stays higher than it should be, and
nothing anywhere reverts.

The documentation's own instruction closes this without naming it: *"Monitor source chain
contract for events."* **Events, not receipts.** A worker built to the docs cannot have
this bug; splitting the files makes that the natural design instead of the disciplined
one.

### 2. Two keys, and one of them is dangerous

The keeper's key spends ETH. On mainnet that is real money. The worker's key spends
tCTC and — unlike the keeper — talks to an external HTTP service whose response it
parses.

Merging them puts a mainnet-gas-paying key inside the process with the widest external
attack surface. Separate processes let the keeper key live somewhere the worker's
dependencies never reach.

### 3. Different failure semantics

The keeper failing is a *deferred* problem: yield accrues in Aave regardless, and the
next successful harvest sweeps all of it. Restart it tomorrow and nothing was lost.

The worker failing is an *accumulating* problem: unproven events pile up, and the
Creditcoin ledger diverges further from Ethereum reality every hour. It also gets more
expensive to catch up (see **Cost**, below).

One wants an alert. The other wants a page.

---

## `keeper.ts`

The whole job:

```
loop every N minutes:
    accrued = adapter.yieldAccrued()
    if accrued >= keeperThreshold:
        adapter.harvest()
```

### Read before you write

The obvious wrong version is a bare cron that calls `harvest()` on a timer.
`_harvest()` reverts below `I_MIN_HARVEST` (checkpoint 1), so a timer-only keeper
burns gas on a guaranteed revert every cycle it fires early. Check `yieldAccrued()`
first — it is a free `view` call — and only then send a transaction.

### The floor is economic, not just anti-dust

`HelperConfig` sets `MIN_HARVEST = 10e6`, i.e. $10. That number was chosen as an
anti-dust guard, and on Sepolia it is fine because testnet gas is free.

**On mainnet it is almost certainly too low.** A harvest is an Aave withdrawal plus an
ERC-20 transfer; at a realistic gas price that can cost more than the $10 it moves. A
keeper that harvests at the contract's floor would destroy value on every call while
appearing to work perfectly.

Two separate limits, and do not conflate them:

- `I_MIN_HARVEST` — the contract's floor. Immutable, on-chain, protects against dust.
- The keeper's own threshold — configurable, off-chain, and **should be higher than the
  contract's on mainnet.** Size it against observed gas: harvest when
  `accrued > k × (gas price × gas used)`, with `k` around 5–10.

State the mainnet number honestly in the submission (per `CLAUDE.md`) while noting that
it does not bind the Sepolia demo.

### Demo mode

The demo shot is *"one `harvest()`, one proof, every borrower's debt falls at once"*.
That wants a button, not a daemon. Give the keeper a `--once` flag that runs exactly one
cycle and exits, and drive the demo with it.

It also wants yield to exist on cue. Aave V4 is not on Sepolia, so the demo runs against
the `MockAaveSpoke` from checkpoint 9's TODO — which means yield is whatever you make it.
Give the mock a way to accrue on demand and the keeper stops needing to wait for time to
pass. That is a demo fixture, not a protocol feature; keep it out of `src/`.

### Operational rules

- **One transaction in flight.** No concurrent harvests — a second one lands below the
  floor and reverts.
- **Stateless by construction.** `yieldAccrued()` is the whole input. Unlike the worker,
  the keeper needs no durable store, because a missed cycle costs nothing: the yield is
  still there next time. Resist adding a database to it.
- **Do not emit anything of its own.** The adapter's `TokensHarvested` is what the worker
  watches. A keeper log line is for you, not for the protocol.

---

## `worker.ts`

The documented flow is five phases. riya adds two steps inside them — an emitter filter
for cost, and a dedupe check — for a working loop of seven:

```
1. monitor   Ethereum logs, filtered by address AND topic0
2. wait      until the block containing the event is attested on Creditcoin
3. prove     request Merkle + continuity proofs from the Proof Builder service
4. check     RiyaASC.isConsumed(key)  →  skip if already done
5. submit    RiyaASC.submit(height, encodedTx, merkleProof, continuityProof)
6. confirm   watch for RiyaASC's ProofConsumed event
7. record    mark the event done in durable storage
```

Steps 1, 2, 3, 5 and 6 are the documentation's *"Monitor → Wait → Generate → Call →
Handle results"*. Steps 4 and 7 are riya's, and both are cost and robustness measures
rather than correctness ones.

### 1 · Monitor — filter on address, not just signature

Two filters:

| Event | Emitter to pin |
|---|---|
| `TokensDepositedConfirmedByEscrow(address,uint256)` | `RiyaEscrow` |
| `TokensHarvested(address,uint256)` | `AaveV4Adapter` |

`RiyaASC._dispatch` already pins both emitters, so an impostor log cannot steal money.
But it `continue`s past impostors, and a transaction containing *only* impostor logs
reverts with `RiyaASC__NoRelevantLog` — **after** you paid to build and submit the proof.

Filtering by address client-side is not a security measure; the contract handles that.
It is a cost measure, and it stops a stranger griefing your CTC balance by emitting
lookalike events all day.

**Use more than one Ethereum RPC.** The docs list this explicitly among the robustness
requirements: *"Following multiple source chain nodes to listen for events in case a node
experiences issues."* A single provider that silently stops delivering logs is the
failure mode that looks like "nothing is happening" rather than like an error, and it is
the hardest one to notice. Two providers, and reconcile.

### 2 · Wait — attestations lag deliberately

From the Creditcoin team's answer in `research/qanda.md`:

> *"Attestcoin intentionally has an amount of blocks behind latest height of source
> chain, to avoid building the attestation chain before the re-orgs happen."*

And attestations are produced at intervals — every 10 or 100 source blocks — not per
block (`research/notes.md`). So a freshly mined Ethereum block is not immediately
provable. The docs give this its own step and its own retry loop (`retryAttestation`) for
exactly that reason.

**The worker's most valuable behaviour is patience.** Poll until the block is covered,
then go. Do not retry-storm the prover in the gap — a proof request for an unattested
block is a request that cannot succeed, no matter how many times you send it.

#### Resolved: there is a second precompile, and it answers this directly

The earlier draft of this checkpoint guessed that the attestation registry was "a separate
surface" and proposed falling back to a `view` call on `verify`. **The guess was right and
the fallback is unnecessary.** riya was only ever looking at *one* precompile:

| Precompile | Address | Answers |
|---|---|---|
| Block Prover | `0x…0FD2` | "did this transaction happen?" |
| **Chain Info** | **`0x…0FD3`** | **"is height N attested yet?"**, and which chains are supported |

`@gluwa/usc-sdk`'s `chainInfo.PrecompileChainInfoProvider` wraps `0x0FD3` and exposes
exactly the missing call:

```ts
getLatestAttestedHeightAndHash(chainKey) -> { height, hash, isAttestation, exists }
getContinuityBounds(chainKey, height)    -> { …, isAttested: boolean }
waitUntilHeightAttested(chainKey, targetHeight, pollIntervalMs?, waitTimeoutMs?)
```

So step 2 is one SDK call, not a polling loop you write.

#### But there are *two* `waitUntilHeightAttested`, and they are not the same

This is the subtle part, and picking the wrong one produces exactly the "retriable error"
the SDK warns about:

| Called on | Source of truth | Means |
|---|---|---|
| `chainInfoProvider` | the `0x0FD3` precompile — **on-chain** | Creditcoin has attested the block |
| `proofBuilder` | the Proof Builder's `/api/v1/attested-height/{chainKey}` — **its in-memory cache** | the *service* can serve a proof for it |

The SDK is explicit that the second "relies on the proof builder service's internal
attestation cache, not directly on-chain data or precompiles," and that "there may be a
delay between on-chain finalization and availability via this API."

**The proof-builder one is the later of the two, and it is the one gating a proof request.**
`offchain/src/worker.ts` currently uses it, which is correct. The on-chain check is still
worth keeping as a log line — it tells you whether a stall is Creditcoin's attestation lag
or the prover's indexing lag, and those page different people.

There is also an `extraDelayMs` parameter, which exists "in case we request the proof from
a different proof builder service due to load balancing." Set it. A load-balanced fleet
means the instance that told you *attested* may not be the instance you ask for the proof.

### 3 · Prove — resolved; the SDK *is* the mapping layer

The earlier draft called for a spike here because two conflicting request shapes were
documented and the response JSON was unknown. **Both are now settled**, and the answer is
that riya should not talk to the prover over HTTP at all.

**The request shape.** `research/notes.md` was right and the sequence diagram was an
abstraction. The SDK's own docstring pins the endpoint:

> *"Service is expected to expose an HTTP endpoint at
> `/api/v1/proof-by-tx/{chainKey}/{transactionHash}`"*

Two parameters, not three. `chainKey` is fixed in the `ProofBuilder` constructor, so the
call site is just `getProof(txHash)` — the block height is derived by the service, which is
why the path form never needed to carry it.

**Which prover URL.** `https://prover.cc3-testnet.creditcoin.network` — the one the SDK's
own examples and docstrings use throughout. `proof-gen-api` does not appear anywhere in the
SDK. Treat the `environments.md` ambiguity as closed in favour of `prover`.

**The response shape**, known exactly, as `ContinuityResponse`:

```ts
{ chainKey, headerNumber, txIndex, txHash, txBytes,
  merkleProof:     { root, siblings: [{ hash, isLeft }] },
  continuityProof: { lowerEndpointDigest, roots: string[] },
  cached, generatedAt }
```

Compare that to what `RiyaASC.submit(height, encodedTx, merkleProof, continuityProof)`
expects (checkpoint 6) and the mapping is `headerNumber → height`, `txBytes → encodedTx`,
and the two proof structs pass straight through. **There is no mapping layer to write** —
which is the whole reason the spike is cancelled rather than merely postponed.

**`chainKey` should be discovered, not hardcoded.** `chainInfoProvider.getSupportedChains()`
returns `{ chainKey, chainId, chainName, chainEncoding }`. Sepolia is `1` on Creditcoin
Testnet, but asserting that at boot — fetch the list, find `chainId === 11155111`, and check
it equals the `I_CHAIN_KEY` the deployed `RiyaASC` was constructed with — turns a silent
misconfiguration into a startup crash. The registries differ per network, and a worker
pointed at the wrong key builds proofs the ASC will reject.

**On the WSS-only concern:** it was wrong, and it was load-bearing for the stack choice.
The SDK's examples and riya's own `worker.ts` both use plain `JsonRpcProvider` against
`https://rpc.cc3-testnet.creditcoin.network`. HTTP works. See **Layout and stack** below —
this is what removes the last argument for viem.

### 4 · Check — `isConsumed`, and what the docs say about tracking

The documentation is explicit that both layers exist:

> *"Avoiding submitting multiple ASC calls for the same event (replay protection is
> handled by the ASC contract, but workers should also track processed events)."*

So: the ASC's `s_consumed` mapping is the guarantee, and the worker's own record is the
efficiency layer. Do both. Checkpoint 6 added a public `isConsumed(bytes32 key)` view
specifically so the worker can check on-chain without paying for a reverting transaction.

Compute the key exactly as the contract does (`src/RiyaASC.sol:199`):

```
txIndex = verifier.calculateTxIndex(merkleProof)
key     = keccak256(abi.encode(chainKey, height, merkleProof.root, txIndex))
```

**The `txIndex` round-trip is now avoidable.** The prover already returns `txIndex` in its
response, so the worker can compute the key with **zero on-chain calls** and only pay for
the `isConsumed` read. Keep `computeTransactionIndex(merkleProof)` (the SDK's wrapper for
the precompile's `calculateTxIndex`) in the test suite as the cross-check that the
prover's `txIndex` and the precompile's derivation agree — but do not call it on the hot
path.

Two typing traps when reproducing `abi.encode` in TypeScript, both of which produce a key
that is wrong-but-plausible and silently disable the dedupe:

- `I_CHAIN_KEY` is `uint64` and `calculateTxIndex` returns `uint64` — **not** `uint256`.
  Encode them as `uint64` or every key mismatches.
- `height` is whatever `submit`'s parameter declares. Read the signature; do not assume.

This is the mismatch the "do not skip this one" test in the **Tests** section exists to
catch.

### 7 · Record — durable, per the docs

My earlier instinct here was that the chain is the source of truth and a local cursor is
a pure optimisation. That is mechanically correct and it is **not** what the docs ask
for. Their robustness list is unambiguous:

> *"Retaining stored records of events in progress in the event of a Worker shutdown"*
> and *"Catching up with any event that might have been missed as a result of an
> unexpected shutdown."*

Note the phrase **in progress**. The interesting state is not "done" — `isConsumed`
answers that — it is the event that was detected, proved, and submitted but whose
outcome the worker never observed because it died mid-flight. Without a record, a restart
has no idea that event ever existed.

So keep a small durable store keyed by `(txHash, logIndex)` with a status:
`detected → attested → proved → submitted → confirmed`. SQLite or a JSON file is plenty
at this scale.

> **Answering the `@question` in `offchain/src/worker.ts`** — *"should we then integrate a
> database, preferably a postgres database?"*
>
> **No, not for this build.** Postgres is the right answer to concurrent writers, and riya
> has exactly one writer by design — step 5 forbids a second. It is also the wrong answer to
> the question the docs actually ask, which is about *surviving a restart*, not about
> throughput or querying.
>
> Use SQLite. It is a file, it is transactional, it needs no process to babysit, and it
> deploys wherever the worker deploys — which matters when Execution Capability is being
> judged on a demo that has to come up on someone else's machine. A Postgres dependency is
> one more container between the judges and a working demo, bought for scale riya does not
> have.
>
> What would change the answer: multiple workers across regions (which step 5 rules out), or
> wanting the store to double as the analytics/reporting surface for the frontend. If the
> second one arrives, that is a read-replica of chain state, not this table — keep the
> worker's crash-recovery store separate from it either way.

On restart:

1. Reload anything not `confirmed`, and resume it from its recorded stage.
2. Rescan the source chain from the last `confirmed` block minus a margin.
3. Let `isConsumed` discard anything the rescan turns up that was already applied.

Together those give the docs' *"catching up with any event that might have been missed"*
with no risk of double-submission — the local store handles the in-flight case, and the
chain handles the ambiguous one.

### 5 · Submit — strictly in source-chain order

**This is the property the contracts cannot enforce, the documentation does not mention,
and the worker owns entirely.**

`LoanLedger._settle` (checkpoint 8) sets a user's `s_marker` to the current
`s_yieldPerShare` when their collateral changes. Whether a depositor shares in a given
harvest is therefore decided by *the order the ASC processed the two proofs* — not by
what happened on Ethereum.

Both directions of disorder are bugs, and they are different bugs:

| Real Ethereum order | Submitted as | Result |
|---|---|---|
| Bob deposits @100, harvest @101 | harvest, then deposit | Bob's marker is set after the harvest. **He loses yield he earned.** |
| harvest @100, Bob deposits @101 | deposit, then harvest | Bob is in `s_totalCollateral` for a harvest predating him. **He is paid out of everyone else's yield.** |

The first shortchanges one user. The second dilutes every other user. Neither reverts,
neither logs anything unusual, and both are invisible until someone reconciles the
numbers by hand.

So:

- **One submission at a time.** A single ordered queue, sorted by
  `(blockNumber, transactionIndex)`, one transaction in flight.
- **No parallelism, ever.** Concurrent submission is the whole bug. If throughput ever
  becomes a real problem, the answer is the precompile's batch overload, not two workers —
  and the batch API turns out to *enforce* riya's ordering rather than threaten it (below).
- **Ordering constrains the retry loops too.** A retry on event *n* must block event
  *n + 1*, not let it overtake. This is the one place where the docs' three independent
  retry loops need a riya-specific constraint bolted on.
- Note that `_dispatch` already orders harvests before deposits *within* a single
  transaction, for the same reason. Across transactions it is the worker's job.

#### Pre-flight: `verifySingle` costs nothing, so always call it

`offchain/src/worker.ts` currently ends at `prover.verifySingle(...)`. That is **not** the
submission — it is a read-only call to the `0x0FD2` precompile that returns a boolean, and
riya's actual write is `RiyaASC.submit(...)`, which calls `verifyAndEmit` internally
(`src/RiyaASC.sol:209`).

That is worth keeping rather than replacing. It gives the worker a **free dry run**: a
malformed or stale proof returns `false` for zero tCTC, instead of reverting a paid
`submit`. The rule:

```
verifySingle(...) === false  →  do not submit; re-request the proof
verifySingle(...) === true   →  submit, and expect it to land
```

Note the division of labour, because it is easy to over-read what the dry run proves. The
precompile answers *"is this proof valid?"*. It says nothing about riya's own guards —
`RiyaASC__NoRelevantLog` and `RiyaASC__TxReverted` can still fire on a proof that passes
`verifySingle` perfectly, because those are checks on the *contents* of a transaction the
precompile has already agreed is real. Pre-flight narrows the failure set; it does not
empty it.

#### The batch path, and its hard limits

When throughput eventually matters, the constraints are fixed and small:

> *"The current `MAX_BATCH_SIZE` is 10 proofs, and these must be within a
> `MAX_BATCH_RANGE` of 1000 blocks."*

`getBatchProof(txHashes)` returns **one shared `continuityProof`** for the whole span plus
per-transaction merkle proofs — which is where the saving comes from, since the continuity
proof is the part that scales with waiting (see **Cost**).

**And the batch API is ordered by construction.** The SDK's `mergeProofs` is blunt about it:

> *"This method expects the proofs to be in order from lowest to highest block number and
> contiguous. Otherwise, the resulting proof will not be usable for proving."*

Read that against step 5's whole argument. riya's ordering invariant is enforced nowhere in
the contracts and is the worker's sole responsibility — but a worker that batches
*cannot* get the order wrong, because an out-of-order batch fails to build at all. The
optimisation and the correctness property point the same way, which is a rare and welcome
alignment. It does not remove the need for the ordered queue (batches must still be
submitted in ascending order relative to each other), but it removes the worst case where a
performance change silently breaks accounting.

### 6 · Confirm — riya has a purpose-built event for this

The docs' final phase: *"Handle results: the worker can listen for events from the ASC
contract to confirm successful execution."*

Checkpoint 6 built exactly that surface. `RiyaASC` emits:

```solidity
event ProofConsumed(bytes32 indexed key, RiyaASCActions indexed action, uint256 value);
```

Match on the `key` you computed at step 4, and the `value` tells you what the ledger
actually moved. That closes the loop: the worker knows not merely that its transaction
mined, but that a specific proof was accepted and a specific amount applied.

Log the pair (source `txHash` → Creditcoin `ProofConsumed`). It is the demo's single most
legible artifact — one line showing an Ethereum transaction and its Creditcoin
consequence — and it is also the first thing you will want when something goes wrong.

---

## Retries: three loops, per the docs

The official flowchart — now saved at [`worker-architecture.png`](../worker-architecture.png)
— is the docs' *"logical flow that a more advanced oracle worker might use"*, and it
confirms this section exactly. It has three retry edges and no others:

```
Monitor → Event detected → Wait for attestation ─┬─ Not yet attested → Retry after delay ─┐
                                                 └─ Block attested                        │
                          Generate proofs ───────┬─ Service error → Retry proof generation ┘
                                                 └─ Proofs generated
                          Call ASC contract ─────┬─ Network error → Retry ASC call
                                                 └─ Transaction submitted
                          ASC verifies synchronously → Business logic executed → Success!
```

**One thing to notice about the diagram: it has no failure terminal.** Every error edge
loops back; the only exit is `Success!`. That is fine as a teaching diagram and wrong as an
operational one — it is precisely the loop-that-never-drains described at the end of this
section. riya's dead-lettering is a deliberate departure from the official flow, not an
omission from it, and the submission should say so rather than quietly diverging.

**Two of the three loops are already written for you.** `waitUntilHeightAttested` polls at
15s and gives up at 15 minutes (both configurable), and the SDK ships
`exponential-backoff` as a direct dependency. Do not hand-roll `retryAttestation`. Do tune
that 15-minute ceiling against measured Creditcoin attestation cadence — it is a default
chosen for a generic chain, and if riya's real lag ever exceeds it the worker will throw on
a block that was going to be attested fine.

The documentation's state machine has three distinct retry points, and they fail for
different reasons and want different backoff:

| Loop | Fails because | Backoff |
|---|---|---|
| `retryAttestation` | the block simply is not attested yet | slow, patient — this is expected, not an error |
| `retryProof` | Proof Builder downtime or connectivity | exponential, capped, with a dead-letter after N attempts |
| `retryASC` | Creditcoin RPC/network, or an out-of-gas | exponential — **but re-check `isConsumed` first**, because a submission that timed out client-side may have mined |

That third row is the one that bites. A transaction whose receipt you never saw is not a
transaction that failed. Re-checking `isConsumed` before resubmitting is what stops the
retry path from turning every network blip into a wasted transaction.

Distinguish permanent from transient failures. `RiyaASC__NoRelevantLog` and
`RiyaASC__TxReverted` are permanent — the event will never become submittable, and
retrying it forever is a loop that never drains. Dead-letter those and alert; retry only
what can plausibly succeed later.

---

## Cost, and why promptness is cheap

From `research/notes.md`:

```
CTC ≈ 2.3×10⁻⁵ + 2.9×10⁻⁷ × (continuity hash count)
```

The continuity proof spans from the last attestation to your block, so its length — and
therefore both the CTC cost and the calldata size — grows with how long you waited. The
docs put the difference at **10–100×** between proving a recently finalised transaction
and proving a historical one.

Combined with step 2, this gives the worker a precise objective:

> **Wait exactly long enough to be attested, and not one block longer.**

It also reframes worker downtime. An outage is not just stale state; it is a bill that
grows while you are down, because every queued event gets more expensive to prove. That
is the concrete reason the worker gets a page and the keeper gets an alert.

---

## Layout and stack

```
offchain/
├── package.json
├── .env                  ← gitignored, two keys, never committed
└── src/
    ├── config.ts         shared: addresses, chainkey, RPCs, prover URL
    ├── abi.ts            generated from forge artifacts, not hand-typed
    ├── store.ts          worker only: the durable record from step 7 (SQLite)
    ├── keeper.ts         Ethereum only
    └── worker.ts         Ethereum → Creditcoin
```

### Correction: ethers v6, not viem

The earlier draft specified viem on two grounds — sharing a library with the Next.js
frontend, and needing `webSocket()` for a WSS-only Creditcoin endpoint. **Both grounds have
since failed**, and the second one was simply wrong:

- `@gluwa/usc-sdk` declares **ethers v6 as a peer dependency**. Every SDK entry point takes
  an ethers `JsonRpcApiProvider` or `Signer`. Using viem would mean writing an adapter
  around the one library that is doing the hard part.
- The WSS-only claim was mistaken. `https://rpc.cc3-testnet.creditcoin.network` is what the
  SDK's own examples use, and it is what `worker.ts` already uses. There is no transport
  problem to solve.

So: **TypeScript + ethers v6 + `@gluwa/usc-sdk`** in `offchain/`. The frontend may keep
whatever it uses; the shared-library argument was never worth much, since `config.ts` and
generated ABIs are the only things that actually cross that boundary.

This is a genuine win for Technical Alignment, not just convenience. The worker now depends
on Creditcoin's own published SDK and calls two Creditcoin precompiles (`0x0FD2` and
`0x0FD3`) through it. "Could this ship on any L2 unchanged?" is not a question this file
invites.

`config.ts` is shared; **nothing else is.** If `keeper.ts` ever needs to import from
`worker.ts` or vice versa, the split has been drawn in the wrong place — go back and
find out why. Note that only the worker takes the SDK dependency — the keeper is pure
ethers against Ethereum, and adding an SDK import to it is the clearest possible signal
that the split has been violated.

Generate `abi.ts` from `out/*.json` rather than pasting ABIs. The event signatures are
load-bearing on both sides of the gap (checkpoint 4), and a hand-copied ABI is one more
place for them to drift. This covers riya's *own* contracts only — the precompile
interfaces come from the SDK, and should not be hand-written at all.

### Two keys, two `.env` entries

`KEEPER_PRIVATE_KEY` holds ETH. `WORKER_PRIVATE_KEY` holds tCTC. Different values, even
in the demo, so the split is real rather than aspirational. `.env` is gitignored —
per `CLAUDE.md`, keep it that way.

---

## What is still unknown

Adopting `@gluwa/usc-sdk` closed three of the five items that were open here. Kept with
their original numbering so the change is legible:

| # | Was | Now |
|---|---|---|
| 1 | Prover response shape; 2 params or 3? | **Resolved.** `ContinuityResponse`; two params, `/api/v1/proof-by-tx/{chainKey}/{txHash}` |
| 2 | Which prover URL | **Resolved.** `https://prover.cc3-testnet.creditcoin.network` |
| 3 | How to check attestation status | **Resolved.** ChainInfo precompile `0x0FD3`, via `waitUntilHeightAttested` |
| 4 | Attestation cadence on testnet | **Still open**, but no longer blocking — see below |
| 5 | A tCTC faucet | **Still open. The one remaining item that can stop the demo dead.** |

**On #4.** The SDK's defaults — poll every 15s, time out at 15 minutes — bound the answer
usefully: the authors expect attestation inside 15 minutes and consider 15s granularity
sensible. That is enough to design the retry loop, so cadence is no longer blocking. It is
still worth *measuring*, because it sets the demo's wall-clock gap between "user deposits on
Sepolia" and "collateral appears on Creditcoin", and that gap is a thing judges watch happen
in real time. Measure it once and script the demo narration around the real number.

**On #5.** Unchanged and now isolated. Every other blocker on this checkpoint has been
retired by the SDK; a worker that cannot pay for `submit()` is the only thing left between
riya and a working vertical slice. Resolve it before writing more structure.

New items the SDK surfaced, none blocking:

6. **Does the Proof Builder require an API key or rate-limit anonymous callers?** The SDK
   constructor takes only a URL and a timeout, which suggests not — but the demo makes a
   burst of requests during catch-up, and discovering a rate limit live is a bad time.
7. **`chainEncoding`.** `getSupportedChains()` returns it per chain and the SDK's encoding
   helpers take it as a parameter. It is handled inside `getProof`, so it should never
   surface — but if the prover ever returns `txBytes` the ASC rejects, this is the first
   place to look.

---

## Tests (checkpoint 9)

Off-chain code, so these are ordinary unit tests, not Foundry:

**Keeper**

- `yieldAccrued() < threshold` → sends no transaction (assert on the mocked client)
- `yieldAccrued() >= threshold` → sends exactly one
- a second cycle while one is in flight → still exactly one

**Worker**

- a log from an impostor address → filtered out before the prover is called
- `isConsumed(key) == true` → no transaction sent
- the computed key matches `RiyaASC`'s — assert the TypeScript `keccak256(abi.encode(...))`
  against the value the deployed contract derives for the same inputs. **Do not skip
  this one**; a mismatch here silently disables the dedupe and every restart re-pays for
  work already done.
- **ordering: given events at (100, 2), (100, 5) and (101, 0) delivered out of order, the
  queue submits them in exactly that sequence.** This is the test that guards the property
  from step 5, and it is the only place in the entire repo where that property is checked.
- a retry on event *n* does not let event *n + 1* overtake it
- a block not yet attested → waits, and does not call the prover
- **crash recovery:** a store containing a `submitted` record whose `ProofConsumed` was
  never seen → on restart, re-checks `isConsumed` rather than resubmitting blind
- a permanent failure (`NoRelevantLog`) → dead-lettered, not retried forever
- **pre-flight:** `verifySingle` returning `false` → no `submit` transaction is sent
- **boot assertion:** `getSupportedChains()` disagreeing with the deployed `RiyaASC`'s
  `I_CHAIN_KEY` → the worker refuses to start rather than building proofs the ASC rejects

---

**Next:** Checkpoint 6 built the contract these two feed. Checkpoint 7 builds `RiyaUSD`,
and checkpoint 8 builds `LoanLedger` — where the ordering the worker guarantees actually
gets consumed.
