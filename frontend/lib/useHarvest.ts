"use client";

import { useCallback } from "react";
import { sepolia } from "wagmi/chains";
import { ADDRESSES, aaveV4AdapterAbi } from "./contracts";
import { useTx, type TxState } from "./useTx";
import { useVault } from "./useVault";

export type HarvestState = {
  tx: TxState;
  /** What a harvest would move right now. */
  available: bigint;
  /** The floor the adapter enforces. Below it, `harvest` reverts rather than wasting gas. */
  floor: bigint;
  /** True when a harvest would actually succeed. */
  ready: boolean;
  harvest: () => Promise<void>;
};

/**
 * Pulls the adapter's accrued yield out in a real Ethereum transaction.
 *
 * Permissionless on purpose, and worth exposing in the UI for that reason: `harvest()`
 * takes no arguments and pays nothing to its caller, so whoever pokes it is doing the
 * protocol a favour at their own gas cost. If riya's keeper stops, any user can keep the
 * loans repaying themselves. That is the whole argument for not gating it, and a button
 * is the clearest way to show it is true.
 *
 * It is also the step that turns continuously rebasing Aave interest into a discrete
 * event — which is the only thing Attestcoin can prove.
 */
export function useHarvest(): HarvestState {
  const tx = useTx(sepolia.id);
  const { vault } = useVault();
  const adapter = ADDRESSES.adapter;

  const ready = Boolean(adapter) && vault.yieldAccrued >= vault.minHarvest;

  return {
    tx,
    available: vault.yieldAccrued,
    floor: vault.minHarvest,
    ready,
    harvest: useCallback(async () => {
      if (!adapter) return;
      await tx.send({ address: adapter, abi: aaveV4AdapterAbi, functionName: "harvest" });
    }, [adapter, tx]),
  };
}
