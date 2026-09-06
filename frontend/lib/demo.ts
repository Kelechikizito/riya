import { ASSUMED_YIELD_RATE_BPS } from "./contracts";

/**
 * The dataset the dashboard falls back to before contracts are deployed.
 *
 * It is deliberately *labelled* as sample data in the UI rather than passed off
 * as live — a judge who spots undisclosed fake numbers discounts everything
 * else on the page. The shape matches the real `LoanLedger` reads exactly, so
 * swapping to live data changes nothing downstream.
 *
 * Numbers follow the worked example in the walkthrough: $1,000 deposited, an
 * opening 10% draw, and yield part-way through retiring it.
 */
export const DEMO_POSITION = {
  collateral: 1_000_000_000n, // $1,000.00
  debt: 61_400_000n, //          $61.40 left of a $100 draw
  repaidByYield: 38_600_000n, // $38.60 retired by yield alone
  credit: 0n,
  score: 19n,
  maxLtvBps: 1_000n,
  selfRepayRateBps: BigInt(
    // collateral * yieldRate / debt, mirroring the contract's own arithmetic
    Math.floor((1_000_000_000 * ASSUMED_YIELD_RATE_BPS) / 61_400_000),
  ),
  rUsdBalance: 61_400_000n,
} as const;

export const DEMO_PROTOCOL = {
  totalCollateral: 184_500_000_000n, // $184,500
  protocolFees: 1_384_000_000n, //      $1,384
} as const;

/** Proven source-chain events, newest first. Mirrors what RiyaASC dispatches. */
export const DEMO_ACTIVITY = [
  {
    kind: "harvest",
    label: "Harvest proven",
    detail: "TokensHarvested · AaveV4Adapter",
    amount: 12_400_000n,
    at: "2 hours ago",
    txHash: "0x7f3a…b21c",
  },
  {
    kind: "borrow",
    label: "Borrowed",
    detail: "rUSD minted on Creditcoin",
    amount: 100_000_000n,
    at: "6 days ago",
    txHash: "0x91de…4a07",
  },
  {
    kind: "harvest",
    label: "Harvest proven",
    detail: "TokensHarvested · AaveV4Adapter",
    amount: 26_200_000n,
    at: "9 days ago",
    txHash: "0x2c88…ff31",
  },
  {
    kind: "deposit",
    label: "Deposit proven",
    detail: "TokensDepositedConfirmedByEscrow · RiyaEscrow",
    amount: 1_000_000_000n,
    at: "14 days ago",
    txHash: "0xa4b1…09e2",
  },
] as const;
