"use client";

import { useReadContracts } from "wagmi";
import { creditcoinTestnet } from "./chains";
import { ADDRESSES, isLive, loanLedgerAbi, riyaUsdAbi } from "./contracts";
import { DEMO_PROTOCOL } from "./demo";

export type Protocol = {
  totalCollateral: bigint;
  /**
   * Lifetime protocol fees, in USDC units. A claim on USDC held in the Ethereum escrow
   * rather than a balance on Creditcoin, and not collectable until writability lands.
   */
  protocolFees: bigint;
  /** Yield distributed per unit of collateral, ever. Scaled by 1e18. */
  yieldPerShare: bigint;
  /**
   * Every rUSD in existence.
   *
   * Deliberately not equal to outstanding debt: settlement from proven yield lowers a
   * borrower's `s_debt` without burning the tokens they already spent, so supply is
   * outstanding debt plus debt retired by yield. Showing both is what makes that visible
   * rather than looking like an accounting error.
   */
  rUsdSupply: bigint;
};

export type ProtocolState = {
  protocol: Protocol;
  live: boolean;
  loading: boolean;
};

/** Protocol-wide totals. Needs no wallet, since none of it is per-user. */
export function useProtocol(): ProtocolState {
  const ledger = ADDRESSES.loanLedger;
  // Pinned for the same reason as `usePosition`: these live on Creditcoin regardless of
  // where the wallet is pointed, and an unpinned read quietly falls back to demo numbers.
  const ledgerContract = {
    address: ledger!,
    abi: loanLedgerAbi,
    chainId: creditcoinTestnet.id,
  } as const;

  const { data, isLoading } = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...ledgerContract, functionName: "s_totalCollateral" },
      { ...ledgerContract, functionName: "s_protocolFees" },
      { ...ledgerContract, functionName: "s_yieldPerShare" },
      {
        address: ADDRESSES.riyaUsd!,
        abi: riyaUsdAbi,
        functionName: "totalSupply",
        chainId: creditcoinTestnet.id,
      },
    ],
    query: { enabled: Boolean(ledger && ADDRESSES.riyaUsd), refetchInterval: 15_000 },
  });

  if (!data) {
    return {
      protocol: { ...DEMO_PROTOCOL, yieldPerShare: 0n, rUsdSupply: 0n },
      live: false,
      loading: isLive() && isLoading,
    };
  }

  const [totalCollateral, protocolFees, yieldPerShare, rUsdSupply] = data;
  return {
    protocol: { totalCollateral, protocolFees, yieldPerShare, rUsdSupply },
    live: true,
    loading: isLoading,
  };
}
