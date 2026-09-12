"use client";

import { useCallback, useState } from "react";
import { sepolia } from "wagmi/chains";
import {
  useAccount,
  useConfig,
  useReadContract,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { waitForTransactionReceipt } from "wagmi/actions";
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
  /** What the escrow may already move. Decides whether an approval is needed at all. */
  allowance: bigint;
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
  const config = useConfig();

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

  /**
   * Already-granted allowance. Read so the approval can be skipped when it is not needed:
   * re-approving an amount the escrow can already move is a wallet prompt that buys
   * nothing, and every extra prompt is another place a demo stalls.
   */
  const { data: allowance } = useReadContract({
    address: ADDRESSES.mockUsd,
    abi: mockUsdAbi,
    functionName: "allowance",
    args: [address!, ADDRESSES.escrow!],
    chainId: sepolia.id,
    query: {
      enabled: Boolean(ADDRESSES.mockUsd && ADDRESSES.escrow && address),
      refetchInterval: 15_000,
    },
  });

  const { data: minDeposit } = useReadContract({
    address: ADDRESSES.escrow,
    abi: riyaEscrowAbi,
    functionName: "I_MIN_DEPOSIT",
    chainId: sepolia.id,
    query: { enabled: Boolean(ADDRESSES.escrow) },
  });

  const deposit = useCallback(
    async (amount: bigint) => {
      const escrow = ADDRESSES.escrow;
      const usd = ADDRESSES.mockUsd;
      if (!escrow || !usd || !address) return;

      setError(null);
      setTxHash(undefined);

      /**
       * Send one transaction and wait for it to be mined.
       *
       * The wait is load-bearing, not politeness. `writeContractAsync` resolves when a
       * transaction is *submitted*, so firing all three back to back meant `deposit` was
       * simulated while `mint` and `approve` were still pending — the escrow saw no
       * balance and no allowance, gas estimation reverted, and the wallet never prompted
       * for the third transaction at all. The flow appeared to stop after the approval.
       */
      const send = async (request: Parameters<typeof writeContractAsync>[0]) => {
        const hash = await writeContractAsync(request);
        await waitForTransactionReceipt(config, { hash, chainId: sepolia.id });
        return hash;
      };

      try {
        if (!onSepolia) {
          setStep("switching");
          await switchChainAsync({ chainId: sepolia.id });
        }

        // Faucet step. Skipped entirely once the balance already covers the deposit, so a
        // second deposit is two transactions rather than three.
        if ((balance ?? 0n) < amount) {
          setStep("minting");
          await send({
            address: usd,
            abi: mockUsdAbi,
            functionName: "mint",
            args: [address, amount - (balance ?? 0n)],
            chainId: sepolia.id,
          });
        }

        if ((allowance ?? 0n) < amount) {
          setStep("approving");
          await send({
            address: usd,
            abi: mockUsdAbi,
            functionName: "approve",
            args: [escrow, amount],
            chainId: sepolia.id,
          });
        }

        setStep("depositing");
        const hash = await send({
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
    [address, allowance, balance, config, onSepolia, switchChainAsync, writeContractAsync],
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
    allowance: allowance ?? 0n,
    minDeposit: minDeposit ?? 100_000_000n,
    available: canDeposit(),
    onSepolia,
    deposit,
    reset,
  };
}
