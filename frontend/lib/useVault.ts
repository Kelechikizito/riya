"use client";

import { useReadContracts } from "wagmi";
import { sepolia } from "wagmi/chains";
import { ADDRESSES, aaveV4AdapterAbi } from "./contracts";

export type Vault = {
  /** What the escrow put in, as Aave confirmed it. */
  principal: bigint;
  /** What Aave holds now. Principal plus whatever it has earned. */
  totalAssets: bigint;
  /** The difference, and the only thing `harvest` is allowed to move. */
  yieldAccrued: bigint;
  /** Smallest harvest worth paying Ethereum gas for. */
  minHarvest: bigint;
};

export type VaultState = {
  vault: Vault;
  /** False when the adapter is not deployed, or the read has not returned yet. */
  live: boolean;
  loading: boolean;
};

const EMPTY: Vault = {
  principal: 0n,
  totalAssets: 0n,
  yieldAccrued: 0n,
  minHarvest: 10_000_000n,
};

/**
 * riya's actual position on Ethereum.
 *
 * These four numbers are the honest version of an APY widget. riya cannot show a live Aave
 * rate without modelling V4's premium and deficit mechanics, and a rate we computed wrongly
 * would be worse than none. What it can show is what the adapter is holding right now, which
 * anyone can check against Etherscan, and which is the figure the whole protocol runs on:
 * everything above `principal` is yield, and `harvest` moves exactly that.
 */
export function useVault(): VaultState {
  const adapter = ADDRESSES.adapter;
  const contract = { address: adapter!, abi: aaveV4AdapterAbi, chainId: sepolia.id } as const;

  const { data, isLoading } = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...contract, functionName: "s_principal" },
      { ...contract, functionName: "totalAssets" },
      { ...contract, functionName: "yieldAccrued" },
      { ...contract, functionName: "I_MIN_HARVEST" },
    ],
    query: { enabled: Boolean(adapter), refetchInterval: 15_000 },
  });

  if (!data) {
    return { vault: EMPTY, live: false, loading: Boolean(adapter) && isLoading };
  }

  const [principal, totalAssets, yieldAccrued, minHarvest] = data;
  return {
    vault: { principal, totalAssets, yieldAccrued, minHarvest },
    live: true,
    loading: isLoading,
  };
}
