"use client";

import { useReadContracts } from "wagmi";
import { ADDRESSES, isLive, loanLedgerAbi } from "./contracts";
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
};

export type ProtocolState = {
  protocol: Protocol;
  live: boolean;
  loading: boolean;
};

/** Protocol-wide totals. Needs no wallet, since none of it is per-user. */
export function useProtocol(): ProtocolState {
  const ledger = ADDRESSES.loanLedger;
  const ledgerContract = { address: ledger!, abi: loanLedgerAbi } as const;

  const { data, isLoading } = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...ledgerContract, functionName: "s_totalCollateral" },
      { ...ledgerContract, functionName: "s_protocolFees" },
      { ...ledgerContract, functionName: "s_yieldPerShare" },
    ],
    query: { enabled: Boolean(ledger), refetchInterval: 15_000 },
  });

  if (!data) {
    return {
      protocol: { ...DEMO_PROTOCOL, yieldPerShare: 0n },
      live: false,
      loading: isLive() && isLoading,
    };
  }

  const [totalCollateral, protocolFees, yieldPerShare] = data;
  return {
    protocol: { totalCollateral, protocolFees, yieldPerShare },
    live: true,
    loading: isLoading,
  };
}
