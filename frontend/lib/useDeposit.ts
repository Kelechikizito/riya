"use client";

import { useCallback, useState } from "react";
import { sepolia } from "wagmi/chains";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { useWaitForTransactionReceipt } from "wagmi";
import { ADDRESSES, canDeposit, mockUsdAbi, riyaEscrowAbi } from "./contracts";

/** Where a deposit has got to. The wait between `proving` and `done` is Creditcoin's. */
export type DepositStep =
  | "idle"
  | "switching"
  | "minting"
  | "approving"
  | "depositing"
  | "proving"
  | "done"
  | "error";

export type DepositState = {
  step: DepositStep;
  error: string | null;
  /** The deposit transaction, once sent. Ethereum, not Creditcoin. */
  txHash: `0x${string}` | undefined;
  balance: bigint;
  minDeposit: bigint;
  available: boolean;
  onSepolia: boolean;
  deposit: (amount: bigint) => Promise<void>;
  reset: () => void;
};

/**
 * Drives a deposit end to end on Ethereum: mint demo dollars, approve, deposit.
 *
 * Three transactions rather than one because `MockUSD` is a faucet token the demo brings
 * with it. Against real USDC the mint step disappears and the other two stay.
 *
 * The hook deliberately stops at `proving`. Nothing the browser does moves collateral onto
 * Creditcoin: the readability worker has to see the event, wait for Creditcoin to attest
 * the block holding it, and submit a proof. That wait is the honest part of the product and
 * the UI says so rather than spinning as though it were still working.
 */
export function useDeposit(): DepositState {
  const { address, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const [step, setStep] = useState<DepositStep>("idle");
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const onSepolia = chainId === sepolia.id;

  const { data: balance } = useReadContract({
    address: ADDRESSES.mockUsd,
    abi: mockUsdAbi,
    functionName: "balanceOf",
    args: [address!],
    chainId: sepolia.id,
    query: { enabled: Boolean(ADDRESSES.mockUsd && address), refetchInterval: 15_000 },
  });

  const { data: minDeposit } = useReadContract({
    address: ADDRESSES.escrow,
    abi: riyaEscrowAbi,
    functionName: "I_MIN_DEPOSIT",
    chainId: sepolia.id,
    query: { enabled: Boolean(ADDRESSES.escrow) },
  });

  useWaitForTransactionReceipt({
    hash: txHash,
    chainId: sepolia.id,
    query: { enabled: Boolean(txHash) },
  });

  const deposit = useCallback(
    async (amount: bigint) => {
      const escrow = ADDRESSES.escrow;
      const usd = ADDRESSES.mockUsd;
      if (!escrow || !usd || !address) return;

      setError(null);
      setTxHash(undefined);

      try {
        if (!onSepolia) {
          setStep("switching");
          await switchChainAsync({ chainId: sepolia.id });
        }

        // Faucet step. Skipped entirely once the balance already covers the deposit, so a
        // second deposit is two transactions rather than three.
        if ((balance ?? 0n) < amount) {
          setStep("minting");
          await writeContractAsync({
            address: usd,
            abi: mockUsdAbi,
            functionName: "mint",
            args: [address, amount - (balance ?? 0n)],
            chainId: sepolia.id,
          });
        }

        setStep("approving");
        await writeContractAsync({
          address: usd,
          abi: mockUsdAbi,
          functionName: "approve",
          args: [escrow, amount],
          chainId: sepolia.id,
        });

        setStep("depositing");
        const hash = await writeContractAsync({
          address: escrow,
          abi: riyaEscrowAbi,
          functionName: "deposit",
          args: [amount],
          chainId: sepolia.id,
        });
        setTxHash(hash);

        // Everything from here is the worker's job, and it happens on another chain.
        setStep("proving");
      } catch (e) {
        setError(e instanceof Error ? e.message.split("\n")[0] : "Deposit failed");
        setStep("error");
      }
    },
    [address, balance, onSepolia, switchChainAsync, writeContractAsync],
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
    setTxHash(undefined);
  }, []);

  return {
    step,
    error,
    txHash,
    balance: balance ?? 0n,
    minDeposit: minDeposit ?? 100_000_000n,
    available: canDeposit(),
    onSepolia,
    deposit,
    reset,
  };
}
