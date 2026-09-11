"use client";

import { useCallback, useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import {
  useAccount,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";

/**
 * Where a single transaction has got to.
 *
 * `signing` and `mining` are deliberately separate. They fail for different reasons and
 * the user can only act on the first: a wallet that never opened is a different problem
 * from a transaction that is in a block and slow.
 */
export type TxStatus = "idle" | "switching" | "signing" | "mining" | "done" | "error";

export type TxState = {
  status: TxStatus;
  error: string | null;
  hash: `0x${string}` | undefined;
  /** True from the moment the wallet opens until the receipt lands. */
  busy: boolean;
  send: (config: SendConfig) => Promise<void>;
  reset: () => void;
};

type SendConfig = {
  address: `0x${string}`;
  abi: readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
};

/**
 * One write, driven to a receipt, on a named chain.
 *
 * riya spans two chains, and which one a write belongs to is not a detail the user should
 * have to manage — borrowing lives on Creditcoin, harvesting lives on Ethereum, and a
 * wallet sitting on the wrong one is the single most likely reason a demo stalls. So the
 * switch is part of sending rather than a precondition the caller checks.
 *
 * Waiting for the receipt is the other half. Wagmi's `isPending` covers the wallet prompt
 * only, so a hook that stopped there would report success while the transaction was still
 * unmined, and the numbers on screen would not have moved yet. Invalidating the query
 * cache on the receipt is what makes the position update without a manual refresh.
 */
export function useTx(chainId: number): TxState {
  const { chainId: current } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const queryClient = useQueryClient();

  /** Only what the hook itself drives. Everything after `sent` comes from the receipt. */
  const [phase, setPhase] = useState<"idle" | "switching" | "signing" | "sent" | "failed">(
    "idle",
  );
  const [sendError, setSendError] = useState<string | null>(null);
  const [hash, setHash] = useState<`0x${string}` | undefined>();

  const receipt = useWaitForTransactionReceipt({ hash, chainId });

  // Derived rather than stored: the receipt query already owns this state, and a copy of
  // it in `useState` would be a second source of truth that has to be kept in step.
  const reverted = phase === "sent" && receipt.isError;
  const status: TxStatus =
    phase === "failed" || reverted
      ? "error"
      : phase === "sent"
        ? receipt.isSuccess
          ? "done"
          : "mining"
        : phase;

  const error = sendError ?? (reverted ? "The transaction was mined but reverted." : null);

  useEffect(() => {
    // Every read in the app is a wagmi query; the position, the protocol totals and the
    // vault all move when any of these writes land, so the blunt invalidation is correct.
    if (status === "done") void queryClient.invalidateQueries();
  }, [status, queryClient]);

  const reset = useCallback(() => {
    setPhase("idle");
    setSendError(null);
    setHash(undefined);
  }, []);

  const send = useCallback(
    async (config: SendConfig) => {
      setSendError(null);
      setHash(undefined);

      try {
        if (current !== chainId) {
          setPhase("switching");
          await switchChainAsync({ chainId });
        }

        setPhase("signing");
        const sent = await writeContractAsync({
          address: config.address,
          abi: config.abi,
          functionName: config.functionName,
          args: config.args,
          chainId,
        } as Parameters<typeof writeContractAsync>[0]);

        setHash(sent);
        setPhase("sent");
      } catch (cause) {
        setPhase("failed");
        // Wallet errors carry a stack of causes; the first line is the part a user can act on.
        setSendError(
          cause instanceof Error ? cause.message.split("\n")[0] : "The transaction failed.",
        );
      }
    },
    [chainId, current, switchChainAsync, writeContractAsync],
  );

  return {
    status,
    error,
    hash,
    busy: status === "switching" || status === "signing" || status === "mining",
    send,
    reset,
  };
}
