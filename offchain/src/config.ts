// Shared settings for both off-chain programs.
//
// This is the *only* module `keeper.ts` and `worker.ts` both import. The day one of them
// needs to import from the other, the split has been drawn in the wrong place — see
// checkpoint 5, "Layout and libraries".

import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";

// `.env` lives at the repo root, next to `foundry.toml`, so the contracts and the
// off-chain programs read one file. Resolved from this module rather than from
// `process.cwd()`, so `npm run worker` works from either directory.
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const rootEnv = join(repoRoot, ".env");
loadEnv({ path: existsSync(rootEnv) ? rootEnv : undefined, quiet: true });

/** Reads a required variable, and names the missing one rather than failing later as `undefined`. */
function required(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

/** Reads an optional variable, falling back to a default. */
function optional(name: string, fallback: string): string {
  const value = process.env[name];
  return value === undefined || value === "" ? fallback : value;
}

function optionalNumber(name: string, fallback: number): number {
  const value = process.env[name];
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`Environment variable ${name} is not a number: ${value}`);
  }
  return parsed;
}

/*//////////////////////////////////////////////////////////////
                            SOURCE CHAIN
//////////////////////////////////////////////////////////////*/

/**
 * Ethereum Sepolia. Per `CLAUDE.md` the source chain can only ever be Ethereum Mainnet or
 * Sepolia, so this is a two-value setting rather than a general multi-chain one.
 */
export const SOURCE_CHAIN_ID = optionalNumber("SOURCE_CHAIN_ID", 11155111);

/**
 * Two Ethereum endpoints, because the docs ask for it: *"Following multiple source chain
 * nodes to listen for events in case a node experiences issues."* A node that quietly stops
 * delivering logs fails in the worst way — it looks like a quiet day rather than an error —
 * so the worker reads from both and takes the union.
 *
 * The fallback is optional. With only one endpoint set the worker still runs, and warns.
 */
export const SOURCE_RPC_URLS: string[] = [
  required("ETH_SEPOLIA_RPC_URL"),
  process.env.ETH_SEPOLIA_RPC_URL_FALLBACK,
].filter((url): url is string => typeof url === "string" && url !== "");

/*//////////////////////////////////////////////////////////////
                             CREDITCOIN
//////////////////////////////////////////////////////////////*/

/** Creditcoin CC3 Testnet. Plain HTTP is fine — the WebSocket-only worry was mistaken. */
export const CREDITCOIN_RPC_URL = required("CREDITCOIN_RPC_URL");

/**
 * Sepolia's key in Creditcoin's registry. `1` on CC3 Testnet, and the numbering differs on
 * Mainnet, so `assertChainKey()` in `worker.ts` confirms this against `getSupportedChains()`
 * and against the deployed `RiyaASC.I_CHAIN_KEY` before any proof is requested.
 */
export const CHAIN_KEY = optionalNumber("CHAIN_KEY", 1);

/** The Proof Builder. This URL is what the SDK's own examples and comments use throughout. */
export const PROVER_URL = optional(
  "PROVER_URL",
  "https://prover.cc3-testnet.creditcoin.network",
);

/*//////////////////////////////////////////////////////////////
                              ADDRESSES
//////////////////////////////////////////////////////////////*/

/** Creditcoin. Lazily read, so `keeper.ts` runs without a deployed `RiyaASC`. */
export const riyaAscAddress = () => required("RIYA_ASC_ADDRESS");

/** Ethereum. The two contracts whose events are the only ones worth paying to prove. */
export const riyaEscrowAddress = () => required("RIYA_ESCROW_ADDRESS");
export const aaveV4AdapterAddress = () => required("AAVE_V4_ADAPTER_ADDRESS");

/*//////////////////////////////////////////////////////////////
                                KEYS
//////////////////////////////////////////////////////////////*/

/** Holds ETH, spends it on `harvest()`. Kept separate from the worker's key on purpose. */
export const keeperPrivateKey = () => required("KEEPER_PRIVATE_KEY");

/** Holds tCTC, spends it on `RiyaASC.submit()`. */
export const workerPrivateKey = () => required("WORKER_PRIVATE_KEY");

/*//////////////////////////////////////////////////////////////
                              TUNABLES
//////////////////////////////////////////////////////////////*/

export const worker = {
  /** Where the crash-recovery store lives. One SQLite file, no separate process. */
  dbPath: optional("WORKER_DB_PATH", "./riya-worker.db"),

  /** First Ethereum block to scan on a cold start, when the store has no history. */
  startBlock: optionalNumber("WORKER_START_BLOCK", 0),

  /** How often to sweep Ethereum for new events. */
  pollIntervalMs: optionalNumber("WORKER_POLL_INTERVAL_MS", 12_000),

  /** `eth_getLogs` range per request. Public endpoints commonly cap this near 10k. */
  logRange: optionalNumber("WORKER_LOG_RANGE", 5_000),

  /**
   * How far back to rescan on restart, per step 7: *"Rescan Ethereum starting a little
   * before the last confirmed block, to cover anything missed entirely."* `isConsumed`
   * throws away whatever the rescan re-finds, so overlap is free and gaps are not.
   */
  rescanOverlapBlocks: optionalNumber("WORKER_RESCAN_OVERLAP", 200),

  /**
   * Passed to `waitUntilHeightAttested`. The SDK explains it exists *"in case we request
   * the proof from a different proof builder service due to load balancing"* — the server
   * that said a block was ready may not be the one you ask for the proof.
   */
  extraDelayMs: optionalNumber("WORKER_EXTRA_DELAY_MS", 3_000),

  /** SDK defaults, surfaced here so the 15-minute ceiling can be raised once measured. */
  attestationPollMs: optionalNumber("WORKER_ATTESTATION_POLL_MS", 15_000),
  attestationTimeoutMs: optionalNumber("WORKER_ATTESTATION_TIMEOUT_MS", 900_000),

  /** Retry caps for the two loops that can fail permanently. */
  proofAttempts: optionalNumber("WORKER_PROOF_ATTEMPTS", 6),
  submitAttempts: optionalNumber("WORKER_SUBMIT_ATTEMPTS", 5),
};

export const keeper = {
  /** How often to read `yieldAccrued()`. A free call, so this can be generous. */
  pollIntervalMs: optionalNumber("KEEPER_POLL_INTERVAL_MS", 300_000),

  /**
   * The keeper's own floor, in the asset's smallest unit (USDC, 6 decimals).
   *
   * This is deliberately *not* the contract's `I_MIN_HARVEST`. That one is fixed at deploy
   * and exists to block dust; this one is an economic decision and on Mainnet belongs well
   * above it, because a harvest withdraws from Aave and then transfers, which at a real gas
   * price can cost more than the $10 the contract would allow. Size it as
   * `accrued > k × (gas price × gas used)` with k around 5–10.
   *
   * The default matches `HelperConfig`'s `MIN_HARVEST = 10e6` because Sepolia gas is free.
   */
  threshold: BigInt(optional("KEEPER_THRESHOLD", "10000000")),
};
