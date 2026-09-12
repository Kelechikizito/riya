"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { creditcoinTestnet } from "./chains";
import {
  ADDRESSES,
  ASSUMED_YIELD_RATE_BPS,
  erc20Abi,
  isLive,
  loanLedgerAbi,
} from "./contracts";
import { DEMO_POSITION } from "./demo";

export type Position = {
  collateral: bigint;
  debt: bigint;
  /**
   * Proven yield not yet applied. Settlement is lazy, so between a harvest landing
   * and the user next touching their position, `debt` reads stale by this much.
   * Showing it is what makes a proof visibly do something.
   */
  pendingYield: bigint;
  repaidByYield: bigint;
  credit: bigint;
  score: bigint;
  maxLtvBps: bigint;
  selfRepayRateBps: bigint;
  rUsdBalance: bigint;
};

/** Debt after applying anything already proven. What the user actually owes. */
export function effectiveDebt(position: Position): bigint {
  return position.pendingYield >= position.debt
    ? 0n
    : position.debt - position.pendingYield;
}

export type PositionState = {
  position: Position;
  /** False when the numbers came from the demo dataset rather than the chain. */
  live: boolean;
  loading: boolean;
  connected: boolean;
};

/**
 * Reads the caller's position from `LoanLedger`, or serves the labelled demo
 * dataset when the contracts aren't deployed / no wallet is connected.
 *
 * The consumer never branches on which one it got — it renders `position` and
 * shows a banner keyed off `live`.
 */
export function usePosition(): PositionState {
  const { address, isConnected } = useAccount();
  const ledger = ADDRESSES.loanLedger;
  const enabled = Boolean(ledger && address);

  // The ledger reads share one ABI, which keeps wagmi's tuple inference happy.
  //
  // `chainId` is not optional here. Without it wagmi reads from whatever chain the wallet
  // happens to be on, and a deposit leaves it on Sepolia — where `LoanLedger` does not
  // exist, so every read fails and the hook silently serves the demo dataset instead of
  // the user's real position. riya is two-sided; a dashboard read has to name its side.
  const ledgerContract = {
    address: ledger!,
    abi: loanLedgerAbi,
    chainId: creditcoinTestnet.id,
  } as const;

  const { data, isLoading } = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...ledgerContract, functionName: "s_collateral", args: [address!] },
      { ...ledgerContract, functionName: "s_debt", args: [address!] },
      { ...ledgerContract, functionName: "s_repaidByYield", args: [address!] },
      { ...ledgerContract, functionName: "s_credit", args: [address!] },
      { ...ledgerContract, functionName: "pendingYield", args: [address!] },
      { ...ledgerContract, functionName: "score", args: [address!] },
      { ...ledgerContract, functionName: "maxLtvBps", args: [address!] },
      {
        ...ledgerContract,
        functionName: "selfRepayRateBps",
        args: [address!, BigInt(ASSUMED_YIELD_RATE_BPS)],
      },
    ],
    query: { enabled, refetchInterval: 10_000 },
  });

  // rUSD is a separate contract with a separate ABI, so it gets its own read.
  const { data: rUsdBalance } = useReadContract({
    address: ADDRESSES.riyaUsd,
    abi: erc20Abi,
    chainId: creditcoinTestnet.id,
    functionName: "balanceOf",
    args: [address!],
    query: {
      enabled: Boolean(ADDRESSES.riyaUsd && address),
      refetchInterval: 15_000,
    },
  });

  if (!enabled || !data) {
    return {
      position: { ...DEMO_POSITION },
      live: false,
      loading: isLive() && isConnected && isLoading,
      connected: isConnected,
    };
  }

  const [
    collateral,
    debt,
    repaidByYield,
    credit,
    pendingYield,
    score,
    maxLtvBps,
    selfRepayRateBps,
  ] = data;

  return {
    position: {
      collateral,
      debt,
      pendingYield,
      repaidByYield,
      credit,
      score,
      maxLtvBps,
      selfRepayRateBps,
      rUsdBalance: rUsdBalance ?? 0n,
    },
    live: true,
    loading: isLoading,
    connected: isConnected,
  };
}
