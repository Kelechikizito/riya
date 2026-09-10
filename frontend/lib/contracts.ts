import type { Address } from "viem";

/**
 * Deployed addresses come from the environment so the same build works against
 * a local anvil, Creditcoin testnet, or a future mainnet deployment.
 *
 * While these are unset the dashboard runs on the labelled demo dataset in
 * `lib/demo.ts` rather than rendering an empty skeleton — see `isLive()`.
 */
export const ADDRESSES = {
  loanLedger: process.env.NEXT_PUBLIC_LOAN_LEDGER_ADDRESS as Address | undefined,
  riyaUsd: process.env.NEXT_PUBLIC_RIYA_USD_ADDRESS as Address | undefined,
  riyaAsc: process.env.NEXT_PUBLIC_RIYA_ASC_ADDRESS as Address | undefined,
  escrow: process.env.NEXT_PUBLIC_RIYA_ESCROW_ADDRESS as Address | undefined,
  adapter: process.env.NEXT_PUBLIC_AAVE_ADAPTER_ADDRESS as Address | undefined,
  /** The Sepolia demo dollar. Only exists because Aave V4 is mainnet-only. */
  mockUsd: process.env.NEXT_PUBLIC_MOCK_USD_ADDRESS as Address | undefined,
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
export const ASSUMED_YIELD_RATE_BPS = Number(
  process.env.NEXT_PUBLIC_YIELD_RATE_BPS ?? 500,
);

/**
 * The slice of LoanLedger the UI actually touches. Kept hand-written rather
 * than generated so it stays readable and reviewable next to the contract.
 */
export const loanLedgerAbi = [
  {
    type: "function",
    name: "s_collateral",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "s_debt",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "s_repaidByYield",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "s_credit",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "s_totalCollateral",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "s_protocolFees",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    // Added after the accumulator: yield that is proven but not yet applied. Between
    // harvests `s_debt` reads stale, and this is the difference. Without it the
    // dashboard shows a debt that does not move when a harvest lands.
    type: "function",
    name: "pendingYield",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "score",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "maxLtvBps",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "selfRepayRateBps",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "yieldRateBps", type: "uint256" },
    ],
    outputs: [{ name: "bps", type: "uint256" }],
  },
  {
    type: "function",
    name: "borrow",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "repay",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "s_yieldPerShare",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "event",
    name: "CollateralAdded",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "assets", type: "uint256", indexed: false },
      { name: "newCollateral", type: "uint256", indexed: false },
      { name: "newTotal", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "YieldDistributed",
    inputs: [
      { name: "gross", type: "uint256", indexed: false },
      { name: "fee", type: "uint256", indexed: false },
      { name: "newYieldPerShare", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "DebtRetired",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "applied", type: "uint256", indexed: false },
      { name: "surplus", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Borrowed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Repaid",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

/**
 * `RiyaASC.ProofConsumed` is the only event that says a source-chain transaction was
 * verified by Creditcoin itself. Everything in the activity feed comes from here, which
 * is what lets the feed claim nothing is asserted by riya.
 */
export const riyaAscAbi = [
  {
    type: "event",
    name: "ProofConsumed",
    inputs: [
      { name: "key", type: "bytes32", indexed: true },
      { name: "action", type: "uint8", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
  },
] as const;

/** `RiyaASCActions`, in declaration order. */
export const PROOF_ACTIONS = ["deposit", "harvest"] as const;
export type ProofAction = (typeof PROOF_ACTIONS)[number];

/** The Sepolia leg. Only what a deposit needs. */
export const riyaEscrowAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "I_MIN_DEPOSIT",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

/** `MockUSD` is a faucet token, so the demo can mint its own dollars. */
export const mockUsdAbi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

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
