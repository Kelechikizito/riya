"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { creditcoinTestnet } from "./chains";
import {
  ADDRESSES,
  PROOF_ACTIONS,
  ProofAction,
  isLive,
  loanLedgerAbi,
  riyaAscAbi,
} from "./contracts";
import { DEMO_ACTIVITY } from "./demo";

export type ActivityEvent = {
  kind: ProofAction | "borrow" | "repay";
  label: string;
  detail: string;
  amount: bigint;
  at: string;
  txHash: string;
  /** Undefined for demo rows, which have no transaction to link to. */
  explorerUrl?: string;
};

export type ActivityState = {
  events: readonly ActivityEvent[];
  live: boolean;
  loading: boolean;
};

/**
 * How far back to look. Creditcoin testnet blocks are fast and most RPC providers cap
 * `eth_getLogs` ranges, so this is a window rather than genesis. A real deployment would
 * put an indexer here; for a demo the last few hours is the interesting part anyway.
 */
const LOOKBACK_BLOCKS = 50_000n;

/** Enough to fill the panel without a wall of RPC calls for block timestamps. */
const MAX_EVENTS = 6;

/**
 * The proven-activity feed.
 *
 * Reads `RiyaASC.ProofConsumed`, which is the only event in the system that means
 * "Creditcoin verified an Ethereum transaction itself". That is the claim the panel makes,
 * so it must not be assembled from anything riya merely asserts. `Borrowed` and `Repaid`
 * come from the ledger and are the user's own actions, labelled as such.
 *
 * Falls back to the labelled demo dataset when the contracts are not deployed.
 */
export function useActivity(): ActivityState {
  const client = usePublicClient({ chainId: creditcoinTestnet.id });
  const asc = ADDRESSES.riyaAsc;
  const ledger = ADDRESSES.loanLedger;
  const enabled = Boolean(client && asc && ledger);

  const { data, isLoading } = useQuery({
    queryKey: ["activity", asc, ledger],
    enabled,
    refetchInterval: 10_000,
    queryFn: async (): Promise<ActivityEvent[]> => {
      if (!client || !asc || !ledger) return [];

      const head = await client.getBlockNumber();
      const fromBlock = head > LOOKBACK_BLOCKS ? head - LOOKBACK_BLOCKS : 0n;

      const [proofs, borrows, repays] = await Promise.all([
        client.getContractEvents({
          address: asc,
          abi: riyaAscAbi,
          eventName: "ProofConsumed",
          fromBlock,
          toBlock: "latest",
        }),
        client.getContractEvents({
          address: ledger,
          abi: loanLedgerAbi,
          eventName: "Borrowed",
          fromBlock,
          toBlock: "latest",
        }),
        client.getContractEvents({
          address: ledger,
          abi: loanLedgerAbi,
          eventName: "Repaid",
          fromBlock,
          toBlock: "latest",
        }),
      ]);

      type Raw = {
        kind: ActivityEvent["kind"];
        amount: bigint;
        blockNumber: bigint;
        txHash: string;
      };

      const raw: Raw[] = [];

      for (const log of proofs) {
        // `action` is the RiyaASCActions enum, and arrives as a number over the wire.
        const action = PROOF_ACTIONS[Number(log.args.action ?? 0)] ?? "deposit";
        raw.push({
          kind: action,
          amount: log.args.value ?? 0n,
          blockNumber: log.blockNumber ?? 0n,
          txHash: log.transactionHash ?? "",
        });
      }
      for (const log of borrows) {
        raw.push({
          kind: "borrow",
          amount: log.args.amount ?? 0n,
          blockNumber: log.blockNumber ?? 0n,
          txHash: log.transactionHash ?? "",
        });
      }
      for (const log of repays) {
        raw.push({
          kind: "repay",
          amount: log.args.amount ?? 0n,
          blockNumber: log.blockNumber ?? 0n,
          txHash: log.transactionHash ?? "",
        });
      }

      raw.sort((a, b) => (b.blockNumber > a.blockNumber ? 1 : -1));
      const recent = raw.slice(0, MAX_EVENTS);

      // One block fetch per distinct block, not per event, since a single proof can carry
      // several logs and a demo run puts most of them in the same handful of blocks.
      const blockNumbers = [...new Set(recent.map((e) => e.blockNumber))];
      const timestamps = new Map<bigint, bigint>();
      await Promise.all(
        blockNumbers.map(async (n) => {
          const block = await client.getBlock({ blockNumber: n });
          timestamps.set(n, block.timestamp);
        }),
      );

      const now = BigInt(Math.floor(Date.now() / 1000));

      return recent.map((e) => ({
        ...e,
        ...describe(e.kind),
        at: relativeTime(now - (timestamps.get(e.blockNumber) ?? now)),
        explorerUrl: `${creditcoinTestnet.blockExplorers.default.url}/tx/${e.txHash}`,
      }));
    },
  });

  if (!enabled || !data) {
    return {
      events: DEMO_ACTIVITY as readonly ActivityEvent[],
      live: false,
      loading: isLive() && isLoading,
    };
  }

  // A fresh deployment has no history yet, and an empty panel reads as broken rather than
  // new. Show the sample set and keep saying it is a sample.
  if (data.length === 0) {
    return {
      events: DEMO_ACTIVITY as readonly ActivityEvent[],
      live: false,
      loading: false,
    };
  }

  return { events: data, live: true, loading: isLoading };
}

function describe(kind: ActivityEvent["kind"]): { label: string; detail: string } {
  switch (kind) {
    case "deposit":
      return {
        label: "Deposit proven",
        detail: "TokensDepositedConfirmedByEscrow · RiyaEscrow",
      };
    case "harvest":
      return {
        label: "Harvest proven",
        detail: "TokensHarvested · AaveV4Adapter",
      };
    case "borrow":
      return { label: "Borrowed", detail: "rUSD minted on Creditcoin" };
    case "repay":
      return { label: "Repaid", detail: "rUSD burned on Creditcoin" };
  }
}

function relativeTime(secondsAgo: bigint): string {
  const s = Number(secondsAgo);
  if (s < 60) return "just now";
  if (s < 3_600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86_400) return `${Math.floor(s / 3_600)} hours ago`;
  return `${Math.floor(s / 86_400)} days ago`;
}
