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

> **Unknown to resolve:** the docs' sequence diagram shows `Worker → Oracle: Check if
> Block Attested`, but `INativeQueryVerifier` exposes only `verify`, `verifyAndEmit` and
> `calculateTxIndex` — none of which answer "is height N attested yet?". The attestation
> registry is a separate surface. Find the actual call before designing the polling loop;
> the fallback is to attempt `verify` (the `view` overload, which costs nothing and
> cannot revert state) and treat `false` as "not yet".

### 3 · Prove — request shape is not yet pinned down

Two descriptions exist and they do not match:

- `research/notes.md`: *"an endpoint like `proof-by-tx/{chain_key}/{tx_hash}`"*
- the docs' sequence diagram: *"Request Proofs (chainKey, blockHeight, txHash)"* — three
  parameters, including a height the path form does not carry.

For the demo, `chain_key = 1` (Sepolia, on Creditcoin Testnet — see
`research/environments.md`). Two further open items from `environments.md` bite here, and
both are the worker's problem:

- **Which prover URL.** The testnet page shows both
  `https://prover.cc3-testnet.creditcoin.network/` and
  `https://proof-gen-api.cc3-testnet.creditcoin.network/`.
- **WSS-only RPC.** Only `wss://rpc.cc3-testnet.creditcoin.network` is documented. That
  blocks `forge script`, but it does **not** block the worker — a long-lived bot with a
  WebSocket transport is the one consumer for which WSS is the natural fit. viem's
  `webSocket()` transport handles it.

> **Do this before writing any code:** hit the prover with a known Sepolia transaction
> hash and print the raw response. The `MerkleProof` / `ContinuityProof` structs
> `RiyaASC.submit` expects are known exactly (checkpoint 6); the JSON the prover returns
> is not, and neither is which field carries `height` or whether `encodedTransaction`
> arrives hex-prefixed. A thirty-minute spike here saves a day of guessing at a mapping
> layer.

### 4 · Check — `isConsumed`, and what the docs say about tracking

The documentation is explicit that both layers exist:

> *"Avoiding submitting multiple ASC calls for the same event (replay protection is
> handled by the ASC contract, but workers should also track processed events)."*

So: the ASC's `s_consumed` mapping is the guarantee, and the worker's own record is the
efficiency layer. Do both. Checkpoint 6 added a public `isConsumed(bytes32 key)` view
specifically so the worker can check on-chain without paying for a reverting transaction.

Compute the key exactly as the contract does:

```
txIndex = verifier.calculateTxIndex(merkleProof)
key     = keccak256(abi.encode(chainKey, height, merkleProof.root, txIndex))
```

Both are cheap reads. Call `isConsumed(key)` and skip if it is `true`.

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
at this scale. On restart:

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
  becomes a real problem, the answer is the precompile's batch `verifyAndEmit` overload
  (which takes arrays and one shared continuity proof), not two workers.
- **Ordering constrains the retry loops too.** A retry on event *n* must block event
  *n + 1*, not let it overtake. This is the one place where the docs' three independent
  retry loops need a riya-specific constraint bolted on.
- Note that `_dispatch` already orders harvests before deposits *within* a single
  transaction, for the same reason. Across transactions it is the worker's job.

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
    ├── keeper.ts         Ethereum only
    └── worker.ts         Ethereum → Creditcoin
```

**TypeScript + viem.** The frontend is already Next.js/TypeScript, so this shares a
language and a wallet library with it, and viem's `webSocket()` transport is what the
Creditcoin WSS-only endpoint needs.

`config.ts` is shared; **nothing else is.** If `keeper.ts` ever needs to import from
`worker.ts` or vice versa, the split has been drawn in the wrong place — go back and
find out why.

Generate `abi.ts` from `out/*.json` rather than pasting ABIs. The event signatures are
load-bearing on both sides of the gap (checkpoint 4), and a hand-copied ABI is one more
place for them to drift.

### Two keys, two `.env` entries

`KEEPER_PRIVATE_KEY` holds ETH. `WORKER_PRIVATE_KEY` holds tCTC. Different values, even
in the demo, so the split is real rather than aspirational. `.env` is gitignored —
per `CLAUDE.md`, keep it that way.

---

## What is still unknown

Honest inventory, because this is the least-specified component in the build:

1. **The prover's response shape**, and whether the request takes two parameters or
   three. Unverified. Blocking. Spike it first.
2. **Which prover URL is correct** on testnet. Two are documented.
3. **How to check attestation status** — the docs show the step, the precompile
   interface does not obviously expose it.
4. **Attestation cadence on Creditcoin Testnet** — 10 blocks or 100? Sets the worker's
   minimum latency and therefore what the demo timeline looks like.
5. **A testnet faucet** for tCTC. Undocumented on the environments page, and the worker
   cannot submit anything without it.

Items 1 and 5 are the two that can stop the demo dead. Resolve them before writing
structure, not after.

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

---

**Next:** Checkpoint 6 built the contract these two feed. Checkpoint 7 builds `RiyaUSD`,
and checkpoint 8 builds `LoanLedger` — where the ordering the worker guarantees actually
gets consumed.
