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
} as const;

/** True once the ledger address is configured — the one contract the UI reads. */
export function isLive(): boolean {
  return Boolean(ADDRESSES.loanLedger);
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
