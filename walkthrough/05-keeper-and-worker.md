# Checkpoint 5: the keeper and the worker

> Part of the riya guided build. Two files to write: `offchain/src/keeper.ts` and
> `offchain/src/worker.ts`. They are two separate programs that do two different jobs.
>
> This is the only checkpoint with no Solidity in it. It also holds one rule that none of
> the contracts can check for you, which is what makes it easy to get wrong and hard to
> notice when you do.

> **Updated after installing [`@gluwa/usc-sdk`](https://docs.attestcoin.org/attestcoin-protocol/dapp-builder-infrastructure/attestcoin-sdk-usc-sdk).**
> The first version of this checkpoint was written from the written docs alone and listed
> five open questions. The SDK is now installed, and its code answers three of them. It
> also changes the library choice to ethers v6 and shows a second built-in contract at
> address `0x0FD3` that the earlier version had missed.
>
> One naming note: Creditcoin renamed "USC" to "Attestcoin Protocol", but the package
> kept the old name, so `usc-sdk` and Attestcoin mean the same thing.

---

## Words used in this file

Read these once and the rest of the page gets much easier.

| Word | What it means here |
|---|---|
| **Source chain** | Ethereum. Where users actually deposit their money. |
| **Attested** | Creditcoin has recorded a summary of an Ethereum block, so it can now check claims about what happened inside that block. |
| **Proof** | A bundle of data showing that one specific Ethereum transaction really sat inside one specific Ethereum block. |
| **Proof Builder** | A web service run by Creditcoin that builds those bundles for you. |
| **Precompile** | A contract built into Creditcoin itself, living at a fixed address. riya uses two of them. |
| **ASC** | The contract on Creditcoin that receives a proof, checks it, and then does something with it. riya's is `RiyaASC`. |
| **Event** | A small record a contract writes when something happens, which programs outside the chain can watch for. |
| **Yield** | The interest riya earns by parking user deposits in Aave. |
| **tCTC** | Creditcoin's test currency, used to pay for transactions on Creditcoin. |

---

## The question this answers

From a comment in `src/adapters/AaveV4Adapter.sol:134`, written next to `harvest()`:

> *"who calls the harvest function to trigger the event, i would assume the readability
> worker, righttt? … The job of the readability worker in CTC is to pick up events,
> c'est fini."*

The second half of that is right, and the first half needs correcting. The worker picks
up events after they exist, and something else has to make them exist in the first place.
That something is the keeper, which is a separate program running on a separate chain,
spending a separate currency, using a separate key.

Two jobs that appear next to each other in a diagram can still be two jobs.

---

## What Creditcoin's docs say

Attestcoin's design uses **two transactions** for every piece of data that crosses from
Ethereum to Creditcoin:

> *"The first transaction must always be submitted by the end user. However, the second
> transaction can be initiated by an off-chain worker on behalf of the user."*

The docs are clear that the worker exists mainly to make life easier for users:

> *"Without a worker, users would need to wait for attestation (several minutes),
> manually generate proofs, format the proof data correctly, and then submit a second
> transaction. With a worker, users only need to sign the initial source chain
> transaction."*

That is the version to lead with in the submission. A riya user does one thing: they
deposit USDC on Ethereum. They never see a proof, never wait around for an attestation,
and never touch Creditcoin at all to get credit for their deposit. The worker is what
buys them that.

Two more points from the docs worth keeping:

- **Their example code is for teaching.** The docs say it is *"not to be directly deployed
  in production"*, so treat any snippet as a shape to copy rather than code to import.
- **Paid relayers are coming.** The docs say *"In the future, 3rd party relayers will offer
  the submission of readability queries as a service. A dApp team may choose to pay a small
  fee per readability query rather than maintaining their own worker."* That belongs in the
  roadmap, because it means riya can hand this job to someone else later, which is a good
  answer to "what happens when your bot goes down".

### Where riya differs from their example

The worked example in the docs is a token bridge, where a user always causes the event.
riya proves two kinds of event, and only one of them works that way:

| Event riya proves | Who sends the Ethereum transaction | Matches the docs' example? |
|---|---|---|
| `TokensDepositedConfirmedByEscrow` | the user, when they deposit | yes |
| `TokensHarvested` | anybody, because `harvest()` is open to all | no |

**The keeper exists because of that second row.** No user stands behind a harvest, so
there is no "first transaction the end user submits" to build on, and the Attestcoin docs
do not cover that case. The keeper belongs to riya rather than to Attestcoin, and the
submission should describe it that way so nobody goes looking for it in Creditcoin's docs.

---

## How the two programs differ

| | **Keeper** | **Worker** |
|---|---|---|
| Part of the Attestcoin design | no, riya added it | yes, this is their component |
| Reads from | Ethereum | Ethereum and Creditcoin |
| Writes to | Ethereum, by calling `adapter.harvest()` | Creditcoin, by calling `RiyaASC.submit()` |
| Aware of the other chain | no | yes |
| Pays fees in | ETH | tCTC |
| Starts work when | `yieldAccrued() >= I_MIN_HARVEST` | a matching event shows up |
| Runs roughly every | hours to days | minutes |
| Has special permissions | no, `harvest()` is open to all | no, `submit()` is open to all |
| If it stops | yield keeps building up in Aave and nothing breaks | Creditcoin's copy of the data falls behind |
| Could you delete it | yes | no |

Read those last two rows together. The keeper is a convenience that saves a person from
pressing a button, while the worker is the only route by which anything reaches Creditcoin
at all. Two components with that much difference in importance deserve separate files,
separate processes, and separate expectations about uptime.

### Neither program is trusted

This is worth saying out loud in the submission, because it is unusual and it costs
nothing to have.

`harvest()` has no permission check on it, and `submit()` is deliberately open to anyone
(checkpoint 6 explains why). So **neither bot holds any power that riya depends on**. If
both processes die, anyone with a wallet can call `harvest()`, anyone with a proof can
call `submit()`, and the protocol keeps working.

That is the difference between a helper that speeds things up and an oracle you have to
trust. riya only has the first kind.

---

## Why these are two files

Tidiness is the weakest reason. Here are the real ones.

### 1. A single merged program would only prove its own harvests

This is the argument that settles it.

Because `harvest()` is open to anyone, a yield farmer, a competing bot, or a curious judge
can call it. When they do, the yield lands in the escrow and the adapter writes a
`TokensHarvested` event, and that harvest is exactly as real as one your keeper caused.

Now picture the merged program written the obvious way, where it calls `harvest()`, takes
the receipt, and proves that receipt. It would miss every harvest it did not cause itself.
The yield would sit in the escrow backing nothing, `s_yieldPerShare` would stay flat, every
borrower's debt would stay higher than it should be, and nothing anywhere would throw an
error to tell you.

The docs close this hole without naming it, by saying *"Monitor source chain contract for
events."* Watching for **events** rather than receipts is what avoids the bug, and keeping
the files separate makes that the natural way to write it.

### 2. Two keys, and one of them spends real money

The keeper's key spends ETH, which on Ethereum mainnet is real money. The worker's key
spends tCTC, and the worker also talks to an outside web service and reads whatever that
service sends back.

Merging them would put the key that spends real money inside the process that has the most
contact with the outside world. Keeping them apart lets the keeper's key live somewhere the
worker's dependencies never reach.

### 3. They fail in different ways

When the keeper fails, the problem waits for you. Yield keeps building up inside Aave, and
the next successful harvest collects all of it. Restart the keeper tomorrow and you have
lost nothing.

When the worker fails, the problem grows. Unproven events pile up, Creditcoin's picture of
Ethereum drifts further out of date every hour, and catching up gets more expensive as time
passes (see **Cost** below).

One of those deserves an email. The other deserves a phone call.

---

## `keeper.ts`

The whole job:

```
every N minutes:
    accrued = adapter.yieldAccrued()
    if accrued >= keeperThreshold:
        adapter.harvest()
```

### Read this before you write it

The tempting wrong version is a plain timer that calls `harvest()` on a schedule.
`_harvest()` rejects any amount below `I_MIN_HARVEST` (checkpoint 1), so a timer-only
keeper wastes gas on a guaranteed failure every time it fires early. Check
`yieldAccrued()` first, which is a free read that costs no gas, and send a transaction
only when the number is big enough.

### The minimum is about economics, not just dust

`HelperConfig` sets `MIN_HARVEST = 10e6`, which is $10. That number was picked to stop
tiny pointless harvests, and it works fine on Sepolia because test gas is free.

**On Ethereum mainnet $10 is probably too low.** A harvest means withdrawing from Aave and
then transferring tokens, and at a realistic gas price that can cost more than the $10 it
moves. A keeper harvesting at the contract's minimum would lose money on every call while
looking like it was working perfectly.

Keep these two limits separate in your head:

- `I_MIN_HARVEST` is the contract's floor. It is fixed at deploy, lives on-chain, and
  exists to block dust.
- The keeper's own threshold is a setting you control off-chain, and **on mainnet it should
  sit well above the contract's floor.** Size it against real gas costs: harvest when
  `accrued > k × (gas price × gas used)`, with `k` somewhere around 5 to 10.

State the honest mainnet figure in the submission, and say clearly that it does not apply
to the Sepolia demo, where gas is free.

### Demo mode

The demo moment is "one harvest, one proof, and every borrower's debt drops at once". That
calls for a button rather than a background process, so give the keeper a `--once` flag
that runs a single cycle and exits, then drive the demo with that.

The demo also needs yield to appear on cue. Aave V4 does not exist on Sepolia, so the demo
runs against the `MockAaveSpoke` from checkpoint 9, which means you decide how much yield
there is. Give the mock a way to add yield on command and the keeper stops having to wait
for real time to pass. That is a demo fixture rather than part of the protocol, so keep it
out of `src/`.

### Rules while it runs

- **One transaction at a time.** Two harvests at once means the second one arrives below
  the floor and fails.
- **Keep it stateless.** `yieldAccrued()` is the only input it needs. A missed cycle costs
  nothing because the yield is still sitting there next time, so the keeper needs no
  database at all. Resist adding one.
- **Have it write no events of its own.** The worker watches the adapter's
  `TokensHarvested`, and any log line the keeper prints is for you rather than for the
  protocol.

---

## `worker.ts`

The docs describe five phases. riya adds two more inside them, one to save money and one
to avoid repeating work, which gives seven steps:

```
1. monitor   watch Ethereum events, filtered by contract address and event type
2. wait      until Creditcoin has attested the block holding that event
3. prove     ask the Proof Builder for the proof bundle
4. check     ask RiyaASC.isConsumed(key), and skip if the answer is yes
5. submit    call RiyaASC.submit(height, encodedTx, merkleProof, continuityProof)
6. confirm   watch for RiyaASC's ProofConsumed event
7. record    save progress somewhere that survives a restart
```

Steps 1, 2, 3, 5 and 6 are the docs' *"Monitor, Wait, Generate, Call, Handle results"*.
Steps 4 and 7 are riya's additions, and they exist to save money and survive crashes
rather than to make the accounting correct.

### 1. Monitor, and filter by address as well as event type

Two filters to set up:

| Event | Contract that must have written it |
|---|---|
| `TokensDepositedConfirmedByEscrow(address,uint256)` | `RiyaEscrow` |
| `TokensHarvested(address,uint256)` | `AaveV4Adapter` |

`RiyaASC._dispatch` already checks both of these, so a fake event from some other contract
can never move money. What it does instead is skip past the fake one, and if a transaction
contains nothing except fake events, the whole call fails with `RiyaASC__NoRelevantLog`
**after** you have already paid to build and submit the proof.

So filtering by address in the worker is about cost rather than safety, since the contract
handles safety. It stops a stranger from draining your tCTC balance by writing lookalike
events all day.

**Use more than one Ethereum RPC provider.** The docs ask for this directly, saying
*"Following multiple source chain nodes to listen for events in case a node experiences
issues."* A provider that quietly stops sending you events fails in the worst possible way,
because it looks like a quiet day rather than an error. Run two and compare what they give
you.

### 2. Wait, because attestations are deliberately behind

From Creditcoin's own answer in `research/qanda.md`:

> *"Attestcoin intentionally has an amount of blocks behind latest height of source
> chain, to avoid building the attestation chain before the re-orgs happen."*

Attestations also arrive in batches, covering every 10 or 100 Ethereum blocks rather than
every single one (`research/notes.md`). A block that was mined seconds ago cannot be proved
yet, which is why the docs give this its own step and its own retry loop.

**Patience is the most valuable thing the worker does here.** Wait until the block is
covered, then move. Hammering the Proof Builder during the gap achieves nothing, because a
request for a block that has no attestation yet cannot succeed however many times you send
it.

#### There is a second precompile, and it answers this question directly

The earlier version of this checkpoint guessed that attestation status lived somewhere
other than the Block Prover, and suggested a workaround. The guess was correct and the
workaround is unnecessary, because riya had only been looking at one of Creditcoin's two
built-in contracts:

| Precompile | Address | Answers |
|---|---|---|
| Block Prover | `0x…0FD2` | "did this transaction really happen?" |
| **Chain Info** | **`0x…0FD3`** | **"has block N been attested yet?"**, plus which chains are supported |

The SDK's `chainInfo.PrecompileChainInfoProvider` wraps `0x0FD3` and gives you exactly the
call that was missing:

```ts
getLatestAttestedHeightAndHash(chainKey) -> { height, hash, isAttestation, exists }
getContinuityBounds(chainKey, height)    -> { …, isAttested: boolean }
waitUntilHeightAttested(chainKey, targetHeight, pollIntervalMs?, waitTimeoutMs?)
```

So step 2 is one call to the SDK rather than a waiting loop you write yourself.

#### Two functions share the name `waitUntilHeightAttested`, and they differ

This part is subtle, and choosing the wrong one causes exactly the retriable error the SDK
warns about.

| Called on | Where it looks | What it tells you |
|---|---|---|
| `chainInfoProvider` | the `0x0FD3` precompile, on-chain | Creditcoin has attested the block |
| `proofBuilder` | the Proof Builder's `/api/v1/attested-height/{chainKey}`, its own memory | the service is ready to build you a proof |

The SDK says plainly that the second one *"relies on the proof builder service's internal
attestation cache, not directly on-chain data or precompiles"*, and that *"there may be a
delay between on-chain finalization and availability via this API."*

**The Proof Builder version is the one that happens last, and it is the one that decides
when you may request a proof.** Your `worker.ts` already uses it, which is the right
choice. Keeping the on-chain check as well is still useful, because comparing the two tells
you whether a delay is coming from Creditcoin's attestations or from the service's
indexing, and those two problems have different fixes.

There is also an `extraDelayMs` setting, which the SDK explains exists *"in case we request
the proof from a different proof builder service due to load balancing"*. Set it, because
the server that told you a block was ready may be a different server from the one you ask
for the proof.

### 3. Prove, and let the SDK do the translating

The earlier version of this checkpoint asked for an experiment here, because two conflicting
descriptions of the request existed and nobody knew the shape of the reply. Both of those
are settled now, and the outcome is that riya should let the SDK talk to the Proof Builder
rather than calling it over HTTP directly.

**The request.** `research/notes.md` had it right, and the diagram in the docs was a
simplification. The SDK's own comment pins the address down:

> *"Service is expected to expose an HTTP endpoint at
> `/api/v1/proof-by-tx/{chainKey}/{transactionHash}`"*

Two values, and `chainKey` is fixed when you build the `ProofBuilder` object, so your call
is just `getProof(txHash)`. The service works out the block height itself, which is why the
address never needed to carry it.

**Which Proof Builder URL.** Use `https://prover.cc3-testnet.creditcoin.network`, which is
what the SDK's examples and comments use throughout. The other candidate, `proof-gen-api`,
appears nowhere in the SDK, so treat the question in `environments.md` as settled.

**The reply**, which the SDK calls `ContinuityResponse`:

```ts
{ chainKey, headerNumber, txIndex, txHash, txBytes,
  merkleProof:     { root, siblings: [{ hash, isLeft }] },
  continuityProof: { lowerEndpointDigest, roots: string[] },
  cached, generatedAt }
```

Line that up against what `RiyaASC.submit(height, encodedTx, merkleProof, continuityProof)`
wants (checkpoint 6) and the whole mapping is `headerNumber` becomes `height`, `txBytes`
becomes `encodedTx`, and the two proof objects pass through untouched. **There is no
translation layer to write**, which is why the experiment is cancelled rather than delayed.

**Look up `chainKey` instead of hardcoding it.** `chainInfoProvider.getSupportedChains()`
returns `{ chainKey, chainId, chainName, chainEncoding }` for every chain. Sepolia is `1` on
Creditcoin Testnet, and checking that at startup turns a quiet misconfiguration into a loud
crash: fetch the list, find the entry whose `chainId` is `11155111`, and confirm it matches
the `I_CHAIN_KEY` the deployed `RiyaASC` was given. The numbering differs between Creditcoin
Testnet and Mainnet, and a worker using the wrong one builds proofs that `RiyaASC` rejects.

**About the WSS-only worry:** it was mistaken, and it was the main reason for an earlier
library choice. The SDK's examples and your own `worker.ts` both use a plain
`JsonRpcProvider` against `https://rpc.cc3-testnet.creditcoin.network`, so ordinary HTTP
works and there is no transport problem to solve. See **Layout and libraries** below.

### 4. Check whether this event was already handled

The docs ask for two layers of protection here:

> *"Avoiding submitting multiple ASC calls for the same event (replay protection is
> handled by the ASC contract, but workers should also track processed events)."*

So `RiyaASC`'s `s_consumed` mapping is the guarantee, and the worker's own record is the
thing that saves money. Build both. Checkpoint 6 added a public `isConsumed(bytes32 key)`
read for exactly this, so the worker can ask the question without paying for a transaction
that would fail.

Work out the key the same way the contract does (`src/RiyaASC.sol:199`):

```
txIndex = verifier.calculateTxIndex(merkleProof)
key     = keccak256(abi.encode(chainKey, height, merkleProof.root, txIndex))
```

**You can skip the `txIndex` lookup now**, because the Proof Builder already returns
`txIndex` in its reply. That lets the worker build the key with no on-chain calls at all and
pay only for the `isConsumed` read. Keep the SDK's `computeTransactionIndex(merkleProof)` in
your test suite as a check that the service's `txIndex` agrees with the precompile's, and
leave it out of the code that runs every cycle.

The types in `submit` are `uint64 height`, `bytes32 root` from the merkle proof, and a
`uint64` chain key and transaction index.

**The mistake that actually breaks this** is reaching for `solidityPacked` instead of
`AbiCoder.defaultAbiCoder().encode`. Solidity's `abi.encode` pads every value out to a full
32 bytes, while `abi.encodePacked` and its ethers equivalent squeeze values together at
their natural width, so the two produce completely different hashes from identical inputs.
The contract uses `abi.encode`, so your TypeScript has to as well.

The widths themselves are more forgiving than they look. Because `abi.encode` pads a
`uint64` out to 32 bytes anyway, writing `uint256` in the TypeScript type list produces
byte-for-byte the same key. Writing `uint64` is still the better habit, since ethers then
rejects any value too big to fit and you find a bad chain key or index at the moment it
appears rather than several steps later.

Here is a known-good example to test against, checked against Solidity with
`cast keccak $(cast abi-encode ...)`:

```
chainKey = 1
height   = 9123456
root     = 0x1111111111111111111111111111111111111111111111111111111111111111
txIndex  = 7

key      = 0xd30497eb9a7e9a3d679a1bbaa0d822fed2d5eaabf13546e6b7082bc2f607fb42
```

The test marked "do not skip this one" in the **Tests** section exists to catch this.

### 5. Submit, strictly in the order things happened on Ethereum

**This is the rule the contracts cannot enforce, the docs never mention, and the worker
owns completely.**

When a user's collateral changes, `LoanLedger._settle` (checkpoint 8) records the current
value of `s_yieldPerShare` against that user. So whether a depositor shares in a given
harvest depends on the order `RiyaASC` processed the two proofs, rather than on what
actually happened on Ethereum.

Getting the order wrong in either direction causes a different bug:

| What happened on Ethereum | What you submitted | What goes wrong |
|---|---|---|
| Bob deposits at block 100, harvest at 101 | harvest first, then deposit | Bob's marker is set after the harvest, so **he loses yield he had earned** |
| harvest at block 100, Bob deposits at 101 | deposit first, then harvest | Bob counts toward a harvest that happened before he arrived, so **he is paid out of everyone else's yield** |

The first case shortchanges one person and the second quietly takes from everybody else.
Neither one throws an error, neither one writes an unusual log, and both stay hidden until
somebody checks the numbers by hand.

So:

- **Submit one at a time.** Keep a single queue sorted by `(blockNumber, transactionIndex)`
  and allow one transaction in flight.
- **Never run submissions in parallel.** Running them at once is the bug itself. If
  throughput ever becomes a genuine problem, the answer is the batch call described below
  rather than a second worker.
- **The ordering rule applies to retries too.** A retry of event *n* has to hold up event
  *n + 1* rather than letting it jump ahead. This is where the docs' three independent retry
  loops need an extra riya-specific constraint added on top.
- Within a single transaction, `_dispatch` already handles harvests before deposits for the
  same reason. Across separate transactions it falls to the worker.

#### Try the proof for free before paying to submit it

Your `worker.ts` currently finishes at `prover.verifySingle(...)`. That call is a free read
from the `0x0FD2` precompile that returns true or false, and riya's real write is
`RiyaASC.submit(...)`, which calls `verifyAndEmit` internally (`src/RiyaASC.sol:209`).

Keep the `verifySingle` call rather than replacing it, because it gives the worker a free
trial run. A broken or stale proof comes back as `false` and costs nothing, which saves you
from a paid `submit` that would have failed:

```
verifySingle(...) === false  ->  skip the submit and request the proof again
verifySingle(...) === true   ->  submit, and expect it to work
```

Be careful about how much the trial run proves. The precompile answers one question, which
is whether the proof itself is valid. riya's own checks are separate, so
`RiyaASC__NoRelevantLog` and `RiyaASC__TxReverted` can still fire on a proof that passes
`verifySingle` perfectly, because those look at what the transaction contained rather than
at whether it happened. The trial run shrinks the list of things that can go wrong without
emptying it.

#### The batch route, and its limits

When throughput starts to matter, the limits are small and fixed:

> *"The current `MAX_BATCH_SIZE` is 10 proofs, and these must be within a
> `MAX_BATCH_RANGE` of 1000 blocks."*

`getBatchProof(txHashes)` returns **one shared continuity proof** covering the whole span,
plus a separate merkle proof per transaction. The saving comes from that sharing, because
the continuity proof is the part that grows the longer you wait (see **Cost**).

**The batch route also enforces riya's ordering rule for you.** The SDK's `mergeProofs` is
direct about it:

> *"This method expects the proofs to be in order from lowest to highest block number and
> contiguous. Otherwise, the resulting proof will not be usable for proving."*

Read that against everything above. riya's ordering rule is checked nowhere in the contracts
and rests entirely on the worker, yet a worker that batches simply cannot get the order
wrong, because an out-of-order batch fails to build in the first place. The speed
improvement and the correctness rule pull in the same direction here, which is a lucky
alignment worth mentioning in the submission. You still need the ordered queue, since
batches have to go out in ascending order relative to each other, but the worst case where
a performance change silently breaks the accounting disappears.

### 6. Confirm, using the event riya built for this

The docs' last phase says *"Handle results: the worker can listen for events from the ASC
contract to confirm successful execution."*

Checkpoint 6 built that surface. `RiyaASC` writes:

```solidity
event ProofConsumed(bytes32 indexed key, RiyaASCActions indexed action, uint256 value);
```

Match on the `key` you worked out in step 4, and `value` tells you how much the ledger
actually moved. That closes the loop, because the worker learns that a specific proof was
accepted and a specific amount applied, which is more than knowing that its transaction went
through.

Log the pair together, the Ethereum `txHash` alongside the Creditcoin `ProofConsumed`. One
line showing an Ethereum transaction and its effect on Creditcoin is the clearest single
artifact the demo produces, and it is also the first thing you will reach for when something
breaks.

### 7. Record your progress somewhere that survives a restart

The instinct here is that the chain is the real source of truth and a local record is only
a speed-up. That is mechanically true, and it is also less than the docs ask for. Their
robustness list is direct about it:

> *"Retaining stored records of events in progress in the event of a Worker shutdown"* and
> *"Catching up with any event that might have been missed as a result of an unexpected
> shutdown."*

Notice the phrase **in progress**. The state worth saving is the event that was detected,
proved, and submitted, but whose outcome the worker never saw because it died partway
through. `isConsumed` already tells you about finished work, so the awkward case is the one
still in flight. Without a record, a restarting worker has no idea that event ever existed.

So keep a small store, keyed by `(txHash, logIndex)`, holding a status that moves through
`detected`, `attested`, `proved`, `submitted`, `confirmed`. A SQLite file is plenty at this
size.

> **Answering the `@question` in `offchain/src/worker.ts`**, which asks whether to add a
> database, preferably Postgres.
>
> **SQLite is the better fit for this build.** Postgres earns its keep when several programs
> write to the same data at once, and riya has one writer on purpose, because step 5 forbids
> a second. The docs are asking about surviving a restart rather than about handling load or
> running queries, and SQLite covers that fully.
>
> SQLite is a single file, it handles transactions safely, it needs no separate process to
> look after, and it travels wherever the worker travels. That last point matters when
> judges are scoring Execution Capability on a demo that has to start up on someone else's
> machine, since a Postgres dependency puts one more container between them and a working
> demo.
>
> Two things would change the answer: running several workers in different regions, which
> step 5 rules out, or wanting this data to feed the frontend's charts and history. If the
> second one arrives, that is a separate read-only copy of chain state, and the worker's
> crash-recovery store should stay its own thing either way.

On restart, do three things:

1. Load anything whose status is short of `confirmed`, and pick it up from the stage it
   reached.
2. Rescan Ethereum starting a little before the last `confirmed` block, to cover anything
   missed entirely.
3. Let `isConsumed` throw away whatever the rescan finds that has already been applied.

Together those give you the catching-up behaviour the docs ask for with no risk of
submitting anything twice, because the local store handles the in-flight case and the chain
handles the cases you are unsure about.

---

## Retries: three loops

The official flowchart is saved at [`worker-architecture.png`](../worker-architecture.png),
described in the docs as the *"logical flow that a more advanced oracle worker might use"*.
It confirms this section, and it has exactly three retry paths:

```
monitor for events
  -> event detected
  -> wait for block attestation
       if not yet attested:  retry after a delay, then check again
  -> generate proofs via the Proof Builder
       if the service errors:  retry proof generation
  -> call the ASC contract with the proofs
       if the network errors:  retry the ASC call
  -> the ASC verifies, business logic runs, done
```

**Notice what the diagram leaves out: there is no failure exit.** Every error path loops
back around, and the only way out is success. That works as a teaching diagram and would
cause trouble in production, because it describes a loop that can never drain. riya adds
dead-lettering for that reason, which is a deliberate difference from the official flow, and
the submission should say so rather than diverging quietly.

**Two of the three loops already exist in the SDK.** `waitUntilHeightAttested` checks every
15 seconds and gives up after 15 minutes, with both values adjustable, and the SDK ships
`exponential-backoff` as a dependency. Write neither of those yourself. Do revisit that
15 minute ceiling once you have measured how long Creditcoin attestations actually take,
because it is a default chosen for chains in general, and if riya's real delay ever exceeds
it the worker will give up on a block that was going to arrive fine.

The three retry points fail for different reasons and want different waiting behaviour:

| Loop | Why it failed | How to wait |
|---|---|---|
| attestation | the block has no attestation yet | slowly and patiently, since this is expected rather than broken |
| proof | the Proof Builder is down or unreachable | back off exponentially, cap it, and give up after N attempts |
| ASC call | Creditcoin's network, or running out of gas | back off exponentially, and **check `isConsumed` first**, because a submission that timed out on your end may have gone through |

That third row is the one that catches people out. A transaction whose receipt you never saw
may well have succeeded, and checking `isConsumed` before resending is what stops every
network hiccup from costing you a duplicate transaction.

Separate permanent failures from temporary ones. `RiyaASC__NoRelevantLog` and
`RiyaASC__TxReverted` are permanent, meaning that event will never become submittable and
retrying forever just fills the queue. Send those to a dead-letter list, raise an alert, and
retry only the things that could plausibly work later.

---

## Cost, and why speed saves money

From `research/notes.md`:

```
CTC ≈ 2.3×10⁻⁵ + 2.9×10⁻⁷ × (number of continuity hashes)
```

A continuity proof stretches from the most recent attestation up to your block, so the
longer you wait, the longer it gets, and both the fee and the transaction size grow with it.
The docs put the gap at **10 to 100 times** between proving something recent and proving
something old.

Put that together with step 2 and the worker has a clear target:

> **Wait exactly long enough for the block to be attested, and no longer.**

It also changes how you think about downtime. An outage leaves your data stale, and it also
runs up a bill while you are down, because every queued event costs more to prove the longer
it sits there. That is the concrete reason the worker gets woken up at night and the keeper
gets an email in the morning.

---

## Layout and libraries

```
offchain/
├── package.json
├── .env                  gitignored, holds two keys, never committed
└── src/
    ├── config.ts         shared: addresses, chain key, RPC URLs, prover URL
    ├── abi.ts            generated from forge output rather than typed by hand
    ├── store.ts          worker only: the saved progress from step 7 (SQLite)
    ├── keeper.ts         Ethereum only
    └── worker.ts         Ethereum to Creditcoin
```

### Use ethers v6

An earlier version of this checkpoint chose viem for two reasons, sharing a library with the
Next.js frontend and needing WebSocket support for Creditcoin. Both reasons have since
fallen away:

- `@gluwa/usc-sdk` lists **ethers v6 as a peer dependency**, and every entry point in it
  expects an ethers provider or signer. Choosing viem would mean writing an adapter around
  the one library doing the difficult part of the job.
- The WebSocket-only claim was wrong. `https://rpc.cc3-testnet.creditcoin.network` is what
  the SDK's examples use and what your `worker.ts` already uses, so plain HTTP is fine.

So `offchain/` runs on **TypeScript, ethers v6, and `@gluwa/usc-sdk`**. The frontend can keep
whatever it uses, since the shared-library argument was always weak: `config.ts` and the
generated ABIs are the only things that cross that boundary.

This also helps the submission's Technical Alignment score, because the worker now runs on
Creditcoin's own published SDK and calls two Creditcoin precompiles through it. "Could this
ship on any L2 unchanged?" is a question this file answers well.

`config.ts` is shared and **nothing else is**. The day `keeper.ts` needs to import from
`worker.ts`, or the other way round, the split has been drawn in the wrong place and it is
worth going back to find out why. Only the worker depends on the SDK, since the keeper is
plain ethers talking to Ethereum, so an SDK import appearing in `keeper.ts` is the clearest
sign that the separation has broken down.

Generate `abi.ts` from `out/*.json` rather than pasting ABIs in by hand. The event
signatures matter on both sides of the gap (checkpoint 4), and a hand-copied ABI is one more
place for them to drift apart. This covers riya's own contracts, since the precompile
interfaces come from the SDK and should never be written by hand.

### Two keys, two entries in `.env`

`KEEPER_PRIVATE_KEY` holds ETH and `WORKER_PRIVATE_KEY` holds tCTC. Use different values
even in the demo, so that the separation is real rather than a story you tell. `.env` stays
gitignored, per `CLAUDE.md`.

---

## Where `worker.ts` stands today

All seven steps are built, and `offchain/` is a runnable TypeScript package rather than a
sketch. Measured against the seven steps:

| Step | State | Where it lives |
|---|---|---|
| 1. monitor | **done** | `Worker.scan` — both events, filtered by address, unioned across two RPC endpoints |
| 2. wait | **done** | `Worker.processOne` — the Proof Builder's wait gates it, the `0x0FD3` bounds check runs alongside, `extraDelayMs` is set |
| 3. prove | **done** | `Worker.processOne`, with `assertChainKey()` confirming the key at startup |
| 4. check | **done** | `replayKey` + `isConsumed`, before any paid call |
| 5. submit | **done** | `verifySingle` as the free trial run, then `submitProof`, drained by `Worker.drain` one at a time in Ethereum's order |
| 6. confirm | **done** | `ProofConsumed` matched on the key, logged beside the Ethereum tx hash |
| 7. record | **done** | `store.ts`, SQLite, statuses `detected → attested → proved → submitted → confirmed` |

The three smaller things flagged in the previous revision are fixed: `tx.blockNumber` is
checked with a clear error for a mistyped or still-pending hash, and the chain key and
Proof Builder URL both moved into `config.ts`.

### The files

```
offchain/
├── package.json          ESM, TypeScript, ethers v6, @gluwa/usc-sdk
├── tsconfig.json
├── .env.example          every variable, documented; real values in the repo-root .env
├── scripts/gen-abi.ts    generates src/abi.ts from Foundry's out/
├── src/
│   ├── config.ts         the only module both programs import
│   ├── abi.ts            GENERATED — `npm run abi` after any contract change
│   ├── store.ts          the SQLite crash-recovery store
│   ├── keeper.ts         Ethereum only, no SDK import
│   └── worker.ts         Ethereum to Creditcoin
└── test/                 14 unit tests, `npm test`
```

Four commands:

```
npm run abi        regenerate src/abi.ts from out/
npm run worker     run the worker
npm run worker -- --once <txHash>    prove one transaction and exit (the demo path)
npm run worker -- --dead             list dead-lettered events
npm run keeper -- --once             one harvest cycle (the demo button)
npm test           14 unit tests, no network needed
npm run typecheck
```

### Two decisions worth recording

**SQLite, not Postgres**, answering the `@question` that used to sit at the top of
`worker.ts`. Postgres earns its keep when several programs write the same data at once, and
riya has one writer on purpose because step 5 forbids a second. Node 24 ships `node:sqlite`
in the standard library, so the store costs no dependency at all and no container stands
between a judge and a running demo.

**The retry policy diverges from Creditcoin's flowchart on purpose.** Their diagram has no
failure exit — every error path loops back — which is a loop that can never drain.
`RiyaASC__NoRelevantLog` and `RiyaASC__TxReverted` are permanent, so the worker dead-letters
them rather than blocking every later event behind an event that will never succeed. The
submission should say so rather than diverging quietly.

### What is not covered

The tests cover the pure logic: key derivation, ordering, crash recovery, resume points, and
failure classification. The remaining cases from the **Tests** section below — the address
filter, `isConsumed` suppressing a submit, `verifySingle` returning false, the startup chain
key check — need either a live Creditcoin connection or a mocking layer, and they are
checkpoint 9's work.

**Nothing past step 4 has run against a live `RiyaASC`,** because none is deployed yet. That
is open question 5 and it has not moved.

---

## Open questions

Installing the SDK answered three of the five questions that were open here. The original
numbering is kept so the change is easy to follow:

| # | The question | Where it stands |
|---|---|---|
| 1 | What shape is the Proof Builder's reply, and does the request take two values or three? | **Answered.** `ContinuityResponse`, and two values, at `/api/v1/proof-by-tx/{chainKey}/{txHash}` |
| 2 | Which Proof Builder URL is the right one? | **Answered.** `https://prover.cc3-testnet.creditcoin.network` |
| 3 | How do you check whether a block is attested? | **Answered.** The Chain Info precompile at `0x0FD3`, through `waitUntilHeightAttested` |
| 4 | How often does Creditcoin Testnet attest? | **Still open**, and no longer blocking |
| 5 | Where do you get tCTC? | **Still open, and the one thing that can stop the demo** |

**On question 4.** The SDK's defaults, checking every 15 seconds and giving up after 15
minutes, bound the answer well enough to design around, so cadence no longer blocks
anything. Measuring it is still worthwhile, because it sets the real gap between "user
deposits on Sepolia" and "collateral shows up on Creditcoin", and judges watch that gap
happen live. Measure it once and write the demo narration around the real number.

**On question 5.** Unchanged, and now on its own. Everything else here has been settled by
the SDK, so a worker with no tCTC to spend is the last thing standing between riya and a
working end-to-end demo. Sort it out before writing more code.

Two new questions the SDK raised, neither of them blocking:

6. **Does the Proof Builder need an API key, or limit how often anonymous callers can ask?**
   The constructor takes only a URL and a timeout, which suggests it does not, though the
   demo sends a burst of requests while catching up and finding a rate limit during the demo
   would be an unpleasant surprise.
7. **What is `chainEncoding` for?** `getSupportedChains()` returns it per chain and the SDK's
   encoding helpers accept it. `getProof` handles it internally, so it should never come up,
   though if the Proof Builder ever returns a `txBytes` that `RiyaASC` rejects, this is the
   first place to look.

---

## Tests (checkpoint 9)

This is off-chain code, so these are ordinary unit tests rather than Foundry tests.

**Keeper**

- `yieldAccrued()` below the threshold sends no transaction
- `yieldAccrued()` at or above the threshold sends exactly one
- a second cycle starting while one is still in flight still sends only one

**Worker**

- an event from the wrong contract address is filtered out before the Proof Builder is
  called
- `isConsumed(key)` returning true means no transaction is sent
- the key your TypeScript builds matches the one the deployed contract derives from the same
  inputs. **Do not skip this test**, because a mismatch silently disables the duplicate check
  and every restart pays again for work already done.
- **ordering:** given events at (100, 2), (100, 5) and (101, 0) arriving out of order, the
  queue submits them in that sequence. This test guards the rule from step 5, and it is the
  only place in the whole repo where that rule is checked.
- a retry of event *n* does not let event *n + 1* overtake it
- a block with no attestation yet makes the worker wait rather than call the Proof Builder
- **crash recovery:** a stored record marked `submitted` whose `ProofConsumed` was never seen
  makes the worker re-check `isConsumed` on restart rather than resubmitting blindly
- a permanent failure such as `NoRelevantLog` goes to the dead-letter list rather than
  retrying forever
- **trial run:** `verifySingle` returning false means no `submit` transaction is sent
- **startup check:** `getSupportedChains()` disagreeing with the deployed `RiyaASC`'s
  `I_CHAIN_KEY` stops the worker from starting

---

**Next:** Checkpoint 6 built the contract these two feed. Checkpoint 7 builds `RiyaUSD`, and
checkpoint 8 builds `LoanLedger`, which is where the ordering the worker guarantees actually
gets used.
