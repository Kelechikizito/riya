// The readability worker — the only path anything reaches Creditcoin by.
//
// It watches Ethereum for `RiyaEscrow` and `AaveV4Adapter` events, waits for Creditcoin to
// attest the block holding them, proves them through the Proof Builder, and feeds
// `RiyaASC.submit()` **in the order things happened on Ethereum**.
//
// Seven steps (checkpoint 5). Creditcoin's docs describe five; steps 4 and 7 are riya's own
// additions, and they exist to save money and survive crashes rather than to make the
// accounting correct:
//
//   1. monitor   watch both events, filtered by contract address as well as signature
//   2. wait      until Creditcoin has attested the block holding the event
//   3. prove     ask the Proof Builder for the proof bundle
//   4. check     ask RiyaASC.isConsumed(key), and skip anything already applied
//   5. submit    call RiyaASC.submit(...), strictly in Ethereum's order
//   6. confirm   match RiyaASC's ProofConsumed event against the key
//   7. record    save progress somewhere that survives a restart

import {
  AbiCoder,
  Contract,
  Interface,
  JsonRpcProvider,
  Wallet,
  keccak256,
  type ContractTransactionResponse,
  type Log,
} from "ethers";
import { backOff } from "exponential-backoff";
import { blockProver, chainInfo, proofProvider } from "@gluwa/usc-sdk";

import { AAVE_V4_ADAPTER_ABI, RIYA_ASC_ABI, RIYA_ESCROW_ABI } from "./abi.js";
import * as config from "./config.js";
import { WorkerStore, type EventRecord } from "./store.js";

/*//////////////////////////////////////////////////////////////
                            REPLAY KEY
//////////////////////////////////////////////////////////////*/

/**
 * Rebuilds the replay key exactly as `RiyaASC.submit` does at src/RiyaASC.sol:199.
 *
 * Must use `defaultAbiCoder` because the contract uses `abi.encode`, which pads every
 * value to 32 bytes. `solidityPacked` is the equivalent of `abi.encodePacked` and packs
 * values at their natural width, so it hashes to something completely different from the
 * same inputs. A wrong key here fails silently: `isConsumed` simply always answers no,
 * and the worker re-pays for work it already did on every restart.
 *
 * Known-good vector, cross-checked against `cast keccak $(cast abi-encode ...)`:
 *   (1, 9123456, 0x11..11, 7)
 *     -> 0xd30497eb9a7e9a3d679a1bbaa0d822fed2d5eaabf13546e6b7082bc2f607fb42
 */
export function replayKey(
  chainKey: number,
  height: number,
  merkleRoot: string,
  txIndex: number,
): string {
  return keccak256(
    AbiCoder.defaultAbiCoder().encode(
      ["uint64", "uint64", "bytes32", "uint64"],
      [chainKey, height, merkleRoot, txIndex],
    ),
  );
}

/*//////////////////////////////////////////////////////////////
                          EVENT FILTERS
//////////////////////////////////////////////////////////////*/

const escrowInterface = new Interface(RIYA_ESCROW_ABI);
const adapterInterface = new Interface(AAVE_V4_ADAPTER_ABI);
const ascInterface = new Interface(RIYA_ASC_ABI);

/** Topics come from the generated ABI so they cannot drift from the deployed contracts. */
const DEPOSIT_TOPIC = escrowInterface.getEvent(
  "TokensDepositedConfirmedByEscrow",
)!.topicHash;
const HARVEST_TOPIC = adapterInterface.getEvent("TokensHarvested")!.topicHash;
const PROOF_CONSUMED_TOPIC = ascInterface.getEvent("ProofConsumed")!.topicHash;

/**
 * Failures that will never succeed however many times they are retried.
 *
 * Both look at *what the transaction contained* rather than at whether it happened, so a
 * proof that passes `verifySingle` perfectly can still hit them. Retrying these forever
 * just fills the queue and blocks every later event behind them, so they are dead-lettered.
 */
const PERMANENT_ERRORS = new Set(["RiyaASC__NoRelevantLog", "RiyaASC__TxReverted"]);

/** What `processOne` concluded, which decides whether the queue may advance. */
type StepOutcome =
  | { status: "confirmed" }
  | { status: "skipped" }
  | { status: "dead"; reason: string }
  | { status: "retry"; reason: string };

/*//////////////////////////////////////////////////////////////
                              WORKER
//////////////////////////////////////////////////////////////*/

export class Worker {
  private readonly sourceProviders: JsonRpcProvider[];
  private readonly creditcoinProvider: JsonRpcProvider;
  private readonly signer: Wallet;
  private readonly chainInfoProvider: chainInfo.PrecompileChainInfoProvider;
  private readonly prover: blockProver.PrecompileBlockProver;
  private readonly proofBuilder: proofProvider.service.ProofBuilder;
  private readonly asc: Contract;
  private readonly store: WorkerStore;

  private running = false;

  constructor(store: WorkerStore) {
    this.store = store;

    this.sourceProviders = config.SOURCE_RPC_URLS.map(
      (url) => new JsonRpcProvider(url),
    );
    if (this.sourceProviders.length < 2) {
      console.warn(
        "Only one Ethereum RPC endpoint configured. Set ETH_SEPOLIA_RPC_URL_FALLBACK — " +
          "a node that quietly stops delivering logs looks like a quiet day, not an error.",
      );
    }

    this.creditcoinProvider = new JsonRpcProvider(config.CREDITCOIN_RPC_URL);
    this.signer = new Wallet(config.workerPrivateKey(), this.creditcoinProvider);

    this.chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(
      this.creditcoinProvider,
    );
    this.prover = new blockProver.PrecompileBlockProver(this.creditcoinProvider);
    this.proofBuilder = new proofProvider.service.ProofBuilder(
      config.CHAIN_KEY,
      config.PROVER_URL,
    );

    // Bound to the signer: `isConsumed` is a free read but `submit` is a paid write.
    this.asc = new Contract(config.riyaAscAddress(), RIYA_ASC_ABI, this.signer);
  }

  /*//////////////////////////////////////////////////////////////
                        TYPED CONTRACT CALLS
  //////////////////////////////////////////////////////////////*/

  // ethers reaches contract methods through a proxy, which types them loosely. Going
  // through `getFunction` instead keeps the call sites readable and puts the argument and
  // return types in one place rather than at every use.

  private chainKeyOnChain(): Promise<bigint> {
    return this.asc.getFunction("I_CHAIN_KEY")() as Promise<bigint>;
  }

  private isConsumed(key: string): Promise<boolean> {
    return this.asc.getFunction("isConsumed")(key) as Promise<boolean>;
  }

  private submitProof(
    height: number,
    encodedTransaction: string,
    merkleProof: unknown,
    continuityProof: unknown,
  ): Promise<ContractTransactionResponse> {
    return this.asc.getFunction("submit")(
      height,
      encodedTransaction,
      merkleProof,
      continuityProof,
    ) as Promise<ContractTransactionResponse>;
  }

  /*//////////////////////////////////////////////////////////////
                            STARTUP CHECK
  //////////////////////////////////////////////////////////////*/

  /**
   * Refuses to start on a chain-key mismatch.
   *
   * The numbering differs between Creditcoin Testnet and Mainnet, and a worker using the
   * wrong one builds proofs that `RiyaASC` rejects — after paying for them. Two things are
   * checked: that Creditcoin's own registry agrees this key means our source chain, and
   * that the deployed `RiyaASC` was given the same one.
   */
  async assertChainKey(): Promise<void> {
    const chains = await this.chainInfoProvider.getSupportedChains();
    const match = chains.find((c) => c.chainId === config.SOURCE_CHAIN_ID);

    if (match === undefined) {
      throw new Error(
        `Creditcoin does not list chainId ${config.SOURCE_CHAIN_ID} as a supported source chain. ` +
          `Supported: ${chains.map((c) => `${c.chainName}(${c.chainId})`).join(", ")}`,
      );
    }
    if (match.chainKey !== config.CHAIN_KEY) {
      throw new Error(
        `Chain key mismatch: config says ${config.CHAIN_KEY}, Creditcoin says ${match.chainKey} ` +
          `for ${match.chainName}. Fix CHAIN_KEY before proving anything.`,
      );
    }

    const deployed = Number(await this.chainKeyOnChain());
    if (deployed !== config.CHAIN_KEY) {
      throw new Error(
        `Deployed RiyaASC at ${config.riyaAscAddress()} was built with chain key ${deployed}, ` +
          `but this worker is configured for ${config.CHAIN_KEY}. Every proof would be rejected.`,
      );
    }

    console.log(
      `Chain key ${config.CHAIN_KEY} confirmed for ${match.chainName} (chainId ${match.chainId}).`,
    );
  }

  /*//////////////////////////////////////////////////////////////
                        STEP 1: MONITOR
  //////////////////////////////////////////////////////////////*/

  /**
   * Sweeps a block range on every configured endpoint and records anything new.
   *
   * Filtering by **address as well as event signature** is about cost rather than safety.
   * `RiyaASC._dispatch` already pins both addresses, so a lookalike event from a stranger's
   * contract can never move money — but an unfiltered worker would pay to build and submit
   * the proof before the contract threw it out, and a transaction carrying nothing else
   * reverts with `RiyaASC__NoRelevantLog` after the money is spent.
   */
  async scan(fromBlock: number, toBlock: number): Promise<number> {
    const filters = [
      { address: config.riyaEscrowAddress(), topic: DEPOSIT_TOPIC, source: "escrow" as const },
      { address: config.aaveV4AdapterAddress(), topic: HARVEST_TOPIC, source: "adapter" as const },
    ];

    let inserted = 0;

    for (const filter of filters) {
      // Every endpoint is asked, and the results are unioned. Two nodes disagreeing is the
      // signal worth having: it means one of them is behind or dropping logs.
      const perProvider = await Promise.all(
        this.sourceProviders.map(async (provider, index) => {
          try {
            return await provider.getLogs({
              address: filter.address,
              topics: [filter.topic],
              fromBlock,
              toBlock,
            });
          } catch (error) {
            console.warn(
              `RPC #${index} failed on ${filter.source} logs ${fromBlock}-${toBlock}: ${describe(error)}`,
            );
            return [] as Log[];
          }
        }),
      );

      const union = new Map<string, Log>();
      for (const logs of perProvider) {
        for (const log of logs) union.set(`${log.transactionHash}:${log.index}`, log);
      }

      const counts = perProvider.map((logs) => logs.length);
      if (new Set(counts).size > 1) {
        console.warn(
          `Ethereum endpoints disagree on ${filter.source} logs ${fromBlock}-${toBlock}: ` +
            `${counts.join(" vs ")}. Taking the union (${union.size}).`,
        );
      }

      for (const log of union.values()) {
        const isNew = this.store.insertDetected({
          txHash: log.transactionHash,
          logIndex: log.index,
          blockNumber: log.blockNumber,
          txIndex: log.transactionIndex,
          source: filter.source,
        });
        if (isNew) {
          inserted++;
          console.log(
            `Detected ${filter.source} event at block ${log.blockNumber} tx ${log.transactionHash}`,
          );
        }
      }
    }

    return inserted;
  }

  /*//////////////////////////////////////////////////////////////
                    STEPS 2-6: ONE EVENT, END TO END
  //////////////////////////////////////////////////////////////*/

  /**
   * Carries a single event from `detected` through to `confirmed`.
   *
   * Every failure comes back as an outcome rather than an exception, because the caller has
   * to decide whether the queue may advance — and for a retriable failure it may not.
   */
  async processOne(record: EventRecord): Promise<StepOutcome> {
    const { txHash, logIndex } = record;

    // STEP 2: WAIT, BECAUSE ATTESTATIONS ARE DELIBERATELY BEHIND.
    //
    // Two functions share the name `waitUntilHeightAttested` and they answer different
    // questions. The Proof Builder's version asks its own indexing cache and is the one
    // that decides when a proof may be requested, so it is the one that gates us. The
    // precompile's version asks Creditcoin on-chain. Both are consulted: when they
    // disagree, the gap tells you whether a delay is Creditcoin's attestation or the
    // service's indexing, and those have different fixes.
    try {
      const bounds = await this.chainInfoProvider.getContinuityBounds(
        config.CHAIN_KEY,
        record.blockNumber,
      );
      if (!bounds.isAttested) {
        console.log(
          `Block ${record.blockNumber} not yet attested on-chain (latest bound ${bounds.childHeight}); waiting.`,
        );
      }

      await this.proofBuilder.waitUntilHeightAttested(
        config.CHAIN_KEY,
        record.blockNumber,
        config.worker.attestationPollMs,
        config.worker.attestationTimeoutMs,
        // The server that said a block was ready may not be the one we ask for the proof.
        config.worker.extraDelayMs,
      );
    } catch (error) {
      // Not a failure, just not ready. Waiting is the most valuable thing this step does —
      // hammering the Proof Builder during the gap cannot succeed however often it is sent.
      return { status: "retry", reason: `attestation wait: ${describe(error)}` };
    }

    if (record.status === "detected") {
      this.store.setStatus(txHash, logIndex, "attested");
    }

    // STEP 3: PROVE.
    //
    // `headerNumber` becomes `height`, `txBytes` becomes `encodedTransaction`, and both
    // proof objects pass through untouched — there is no translation layer to write.
    // Backed off exponentially, because a Proof Builder outage is temporary but not brief.
    let proof;
    try {
      proof = await backOff(
        async () => {
          const result = await this.proofBuilder.getProof(txHash);
          if (!result.success || !result.data) {
            throw new Error(result.error ?? "proof builder returned no data");
          }
          return result.data;
        },
        {
          numOfAttempts: config.worker.proofAttempts,
          startingDelay: 1_000,
          maxDelay: 30_000,
          jitter: "full",
        },
      );
    } catch (error) {
      this.store.recordAttempt(txHash, logIndex, describe(error));
      return { status: "retry", reason: `proof generation: ${describe(error)}` };
    }

    const { headerNumber, txIndex, txBytes, merkleProof, continuityProof } = proof;

    // STEP 4: HAS THIS ALREADY BEEN APPLIED?
    //
    // The Proof Builder hands back `txIndex`, so the key costs no on-chain call at all and
    // the only spend here is the free `isConsumed` read. Ask before verifying: a used key
    // makes everything below it pointless.
    const key = replayKey(config.CHAIN_KEY, headerNumber, merkleProof.root, txIndex);
    this.store.setStatus(txHash, logIndex, "proved", { replayKey: key });

    if (await this.isConsumed(key)) {
      console.log(`Skipping ${txHash}: already applied as ${key}`);
      this.store.setStatus(txHash, logIndex, "confirmed", { replayKey: key });
      return { status: "skipped" };
    }

    // STEP 5a: THE FREE TRIAL RUN.
    //
    // `verifySingle` is a free read against the 0x0FD2 precompile. A broken or stale proof
    // comes back false and costs nothing, which saves a paid `submit` that would have
    // failed. It only answers whether the proof is valid, though — riya's own checks are
    // separate, so `NoRelevantLog` and `TxReverted` can still fire after this passes.
    const valid = await this.prover.verifySingle(
      config.CHAIN_KEY,
      headerNumber,
      txBytes,
      merkleProof,
      continuityProof,
    );
    if (!valid) {
      this.store.recordAttempt(txHash, logIndex, "verifySingle returned false");
      return { status: "retry", reason: "proof failed the free trial run; will re-request" };
    }

    // STEP 5b: SUBMIT, AND PAY FOR IT.
    let receipt;
    try {
      receipt = await backOff(
        async () => {
          // Re-checked inside the retry loop on purpose: a submission whose receipt we
          // never saw may well have gone through, and this is what stops every network
          // hiccup from costing a duplicate transaction.
          if (await this.isConsumed(key)) return null;

          const tx = await this.submitProof(
            headerNumber,
            txBytes,
            merkleProof,
            continuityProof,
          );
          this.store.setStatus(txHash, logIndex, "submitted", {
            replayKey: key,
            creditcoinTxHash: tx.hash,
          });
          return await tx.wait();
        },
        {
          numOfAttempts: config.worker.submitAttempts,
          startingDelay: 2_000,
          maxDelay: 30_000,
          jitter: "full",
          retry: (error) => permanentError(error) === null,
        },
      );
    } catch (error) {
      const permanent = permanentError(error);
      this.store.recordAttempt(txHash, logIndex, describe(error));
      if (permanent !== null) {
        return { status: "dead", reason: permanent };
      }
      return { status: "retry", reason: `submit: ${describe(error)}` };
    }

    if (receipt === null) {
      console.log(`Skipping ${txHash}: a previous attempt landed after all (${key})`);
      this.store.setStatus(txHash, logIndex, "confirmed", { replayKey: key });
      return { status: "skipped" };
    }

    // STEP 6: CONFIRM, USING THE EVENT RIYA BUILT FOR THIS.
    //
    // Knowing the transaction went through is less than knowing a specific proof was
    // accepted and a specific amount applied, which is what `ProofConsumed` carries.
    const consumed = (receipt.logs as Log[])
      .filter((log) => log.topics[0] === PROOF_CONSUMED_TOPIC)
      .map((log) => ascInterface.parseLog({ topics: [...log.topics], data: log.data }))
      .find((parsed) => parsed?.args.key === key);

    if (!consumed) {
      // The submit succeeded, so the ledger moved; only our confirmation is missing.
      // Worth a loud line rather than a retry, which would only spend money again.
      console.warn(
        `submit for ${txHash} succeeded (cc tx ${receipt.hash}) but no ProofConsumed matched ${key}`,
      );
    } else {
      // The one log line the demo is built around, and the first thing to reach for when
      // something breaks: an Ethereum transaction beside its effect on Creditcoin.
      console.log(
        `CONFIRMED  eth ${txHash}  ->  cc ${receipt.hash}  ` +
          `action=${consumed.args.action}  value=${consumed.args.value}  key=${key}`,
      );
    }

    this.store.setStatus(txHash, logIndex, "confirmed", {
      replayKey: key,
      creditcoinTxHash: receipt.hash,
    });
    return { status: "confirmed" };
  }

  /*//////////////////////////////////////////////////////////////
                        THE ORDERED QUEUE
  //////////////////////////////////////////////////////////////*/

  /**
   * Drains pending events **one at a time, in Ethereum's order**.
   *
   * This is the rule the contracts cannot enforce, the docs never mention, and the worker
   * owns completely. `LoanLedger._settle` stamps the current `s_yieldPerShare` against a
   * user whenever their collateral changes, so whether a depositor shares in a given
   * harvest depends on the order `RiyaASC` processed the two proofs rather than on what
   * happened on Ethereum. Getting it wrong either shortchanges one person or pays them out
   * of everyone else's yield, and neither one throws an error or writes an unusual log.
   *
   * Two consequences, both deliberate:
   *
   *  - Nothing runs in parallel. Running submissions at once *is* the bug. If throughput
   *    ever matters the answer is the batch call, not a second worker.
   *  - **A retriable failure stops the drain.** Event *n* holding up event *n + 1* is the
   *    point; letting the successor overtake while *n* waits is the same reordering bug
   *    arriving by a slower route.
   */
  async drain(): Promise<void> {
    for (const record of this.store.pending()) {
      const outcome = await this.processOne(record);

      switch (outcome.status) {
        case "confirmed":
        case "skipped":
          continue;

        case "dead":
          // Permanent: this event will never become submittable. Park it, shout about it,
          // and carry on — leaving it in the queue would block everything behind it
          // forever. Creditcoin's own flowchart has no failure exit at all, which is a
          // loop that can never drain; this is riya diverging from it on purpose.
          console.error(
            `DEAD-LETTER ${record.txHash}#${record.logIndex}: ${outcome.reason}`,
          );
          this.store.setStatus(record.txHash, record.logIndex, "dead", {
            lastError: outcome.reason,
          });
          continue;

        case "retry":
          // Temporary. Stop here rather than skipping ahead, and pick this same event up
          // on the next cycle.
          console.log(
            `Holding at ${record.txHash}#${record.logIndex}: ${outcome.reason}`,
          );
          return;
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                              RUN LOOP
  //////////////////////////////////////////////////////////////*/

  /**
   * Scan, then drain, forever.
   *
   * On restart this recovers in the three steps step 7 asks for: anything short of
   * `confirmed` is still in `pending()` and resumes from the stage it reached; the scan
   * starts a little before the earliest unfinished block, so anything missed entirely is
   * picked up; and `isConsumed` throws away whatever the rescan re-finds that has already
   * been applied. The local store handles the in-flight case, the chain handles the rest,
   * and nothing gets submitted twice.
   */
  async start(): Promise<void> {
    await this.assertChainKey();

    this.running = true;
    let cursor = this.store.resumeFromBlock(
      config.worker.startBlock,
      config.worker.rescanOverlapBlocks,
    );

    const dead = this.store.deadLettered();
    if (dead.length > 0) {
      console.warn(`${dead.length} dead-lettered event(s) need a human. Use --dead to list.`);
    }
    console.log(`Worker starting. Scanning Ethereum from block ${cursor}.`);

    while (this.running) {
      try {
        const head = await this.headBlock();
        if (head !== null && head >= cursor) {
          const to = Math.min(head, cursor + config.worker.logRange - 1);
          await this.scan(cursor, to);
          cursor = to + 1;
        }
        await this.drain();
      } catch (error) {
        console.error(`Cycle failed: ${describe(error)}`);
      }
      await sleep(config.worker.pollIntervalMs);
    }
  }

  stop(): void {
    this.running = false;
  }

  /** The highest block every endpoint agrees exists, so a lagging node cannot skip a range. */
  private async headBlock(): Promise<number | null> {
    const heads = await Promise.all(
      this.sourceProviders.map((p) => p.getBlockNumber().catch(() => null)),
    );
    const seen = heads.filter((h): h is number => h !== null);
    return seen.length === 0 ? null : Math.min(...seen);
  }

  /** Runs one event to completion by hash. Useful for the demo and for debugging. */
  async once(txHash: string): Promise<void> {
    await this.assertChainKey();

    const tx = await this.sourceProviders[0]!.getTransaction(txHash);
    if (tx === null) {
      throw new Error(`No such transaction on Ethereum: ${txHash}`);
    }
    if (tx.blockNumber === null) {
      throw new Error(`Transaction ${txHash} is still pending; nothing to prove yet.`);
    }

    const receipt = await this.sourceProviders[0]!.getTransactionReceipt(txHash);
    const relevant = (receipt?.logs ?? []).filter(
      (log) =>
        (log.address.toLowerCase() === config.riyaEscrowAddress().toLowerCase() &&
          log.topics[0] === DEPOSIT_TOPIC) ||
        (log.address.toLowerCase() === config.aaveV4AdapterAddress().toLowerCase() &&
          log.topics[0] === HARVEST_TOPIC),
    );
    if (relevant.length === 0) {
      throw new Error(
        `${txHash} carries no RiyaEscrow or AaveV4Adapter event. RiyaASC would revert with ` +
          `RiyaASC__NoRelevantLog after you paid for the proof.`,
      );
    }

    for (const log of relevant) {
      this.store.insertDetected({
        txHash,
        logIndex: log.index,
        blockNumber: tx.blockNumber,
        txIndex: tx.index,
        source:
          log.topics[0] === DEPOSIT_TOPIC ? ("escrow" as const) : ("adapter" as const),
      });
    }

    await this.drain();
  }
}

/*//////////////////////////////////////////////////////////////
                             HELPERS
//////////////////////////////////////////////////////////////*/

/** Names a permanent revert, or returns null when the failure might work later. */
export function permanentError(error: unknown): string | null {
  const named = (error as { revert?: { name?: string } })?.revert?.name;
  if (named !== undefined && PERMANENT_ERRORS.has(named)) return named;

  const data = (error as { data?: string })?.data;
  if (typeof data === "string" && data.length >= 10) {
    try {
      const parsed = ascInterface.parseError(data);
      if (parsed !== null && PERMANENT_ERRORS.has(parsed.name)) return parsed.name;
    } catch {
      // Not one of ours; treat as retriable.
    }
  }
  return null;
}

function describe(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/*//////////////////////////////////////////////////////////////
                            ENTRYPOINT
//////////////////////////////////////////////////////////////*/

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const store = new WorkerStore(config.worker.dbPath);

  try {
    if (args[0] === "--dead") {
      const dead = store.deadLettered();
      if (dead.length === 0) {
        console.log("No dead-lettered events.");
        return;
      }
      for (const record of dead) {
        console.log(
          `${record.txHash}#${record.logIndex}  block ${record.blockNumber}  ${record.lastError}`,
        );
      }
      return;
    }

    const worker = new Worker(store);

    // `--once <txHash>` proves a single transaction and exits, which is what the demo runs.
    if (args[0] === "--once") {
      const txHash = args[1];
      if (txHash === undefined) throw new Error("Usage: npm run worker -- --once <txHash>");
      await worker.once(txHash);
      return;
    }

    const shutdown = () => {
      console.log("Shutting down after the current event.");
      worker.stop();
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    await worker.start();
  } finally {
    store.close();
  }
}

// Only runs when executed directly, so the tests can import `replayKey` without starting a worker.
if (process.argv[1] !== undefined && import.meta.url.endsWith(process.argv[1].split("/").pop()!)) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
