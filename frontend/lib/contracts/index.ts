import type { Address } from "viem";

import { DEPLOYED } from "./addresses";

export * from "./abis";
export * from "./addresses";

/**
 * Deployed addresses, resolved once.
 *
 * The defaults are generated into `addresses.ts` from `deployments/`, which the deploy
 * itself wrote — so a fresh checkout points at the live system with no setup. The
 * `NEXT_PUBLIC_*` variables still win where they are set, which is what lets the same
 * build run against a local anvil or a future mainnet deployment.
 *
 * Each variable is read as a literal rather than through a loop: Next.js inlines
 * `process.env.NEXT_PUBLIC_*` at build time by textual substitution, and a computed key
 * is simply not replaced.
 */
export const ADDRESSES = {
  loanLedger: (process.env.NEXT_PUBLIC_LOAN_LEDGER_ADDRESS ?? DEPLOYED.loanLedger) as
    | Address
    | undefined,
  riyaUsd: (process.env.NEXT_PUBLIC_RIYA_USD_ADDRESS ?? DEPLOYED.riyaUsd) as Address | undefined,
  riyaAsc: (process.env.NEXT_PUBLIC_RIYA_ASC_ADDRESS ?? DEPLOYED.riyaAsc) as Address | undefined,
  escrow: (process.env.NEXT_PUBLIC_RIYA_ESCROW_ADDRESS ?? DEPLOYED.escrow) as Address | undefined,
  adapter: (process.env.NEXT_PUBLIC_AAVE_ADAPTER_ADDRESS ?? DEPLOYED.adapter) as
    | Address
    | undefined,
  /** The Sepolia demo dollar. Only exists because Aave V4 is mainnet-only. */
  mockUsd: (process.env.NEXT_PUBLIC_MOCK_USD_ADDRESS ?? DEPLOYED.mockUsd) as Address | undefined,
} as const;

/** True once the ledger address is configured — the one contract the UI reads. */
export function isLive(): boolean {
  return Boolean(ADDRESSES.loanLedger);
}

/** True once a deposit can actually be made, which needs the whole Sepolia leg. */
export function canDeposit(): boolean {
  return Boolean(ADDRESSES.escrow && ADDRESSES.mockUsd);
}

/**
 * The observed Aave supply APY, in basis points. `selfRepayRateBps` takes this
 * as an argument rather than reading an oracle, so the frontend owns the number.
 */
export const ASSUMED_YIELD_RATE_BPS = Number(process.env.NEXT_PUBLIC_YIELD_RATE_BPS ?? 500);

/** `RiyaASCActions`, in declaration order. */
export const PROOF_ACTIONS = ["deposit", "harvest"] as const;
export type ProofAction = (typeof PROOF_ACTIONS)[number];

/**
 * Not a riya contract, so it is not generated: this is the slice of ERC-20 the UI reads
 * off whatever token it is pointed at.
 */
export const erc20Abi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
] as const;
