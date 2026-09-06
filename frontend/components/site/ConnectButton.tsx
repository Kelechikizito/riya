"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { useHydrated } from "@/lib/hydration";
import { creditcoinTestnet } from "@/lib/chains";
import { shortAddress } from "@/lib/format";

/**
 * Connect / wrong-network / connected, in one control.
 *
 * Rendered only after mount: wagmi hydrates connection state on the client, so
 * server-rendering "Connect wallet" and then swapping it for an address is a
 * hydration mismatch. A fixed-width skeleton holds the space so the nav does
 * not shift.
 */
export function ConnectButton({ compact = false }: { compact?: boolean }) {
  const hydrated = useHydrated();

  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const base =
    "cursor-pointer rounded-full border px-4 py-2 text-sm font-medium transition-colors duration-200";

  if (!hydrated) {
    return (
      <span
        aria-hidden="true"
        className={`inline-block h-9 rounded-full border border-line ${
          compact ? "w-full" : "w-[8.5rem]"
        }`}
      />
    );
  }

  if (!isConnected) {
    const connector = connectors[0];
    return (
      <button
        type="button"
        disabled={isPending || !connector}
        onClick={() => connector && connect({ connector })}
        className={`${base} border-line text-ink hover:border-muted hover:bg-surface disabled:cursor-not-allowed disabled:text-faint ${
          compact ? "w-full" : ""
        }`}
      >
        {isPending ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }

  if (chainId !== creditcoinTestnet.id) {
    return (
      <button
        type="button"
        onClick={() => switchChain({ chainId: creditcoinTestnet.id })}
        className={`${base} border-credit-400/40 text-credit-400 hover:bg-credit-400/10 ${
          compact ? "w-full" : ""
        }`}
      >
        Switch to Creditcoin
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={() => disconnect()}
      title="Disconnect"
      className={`${base} group border-line font-mono text-ink hover:border-muted hover:bg-surface ${
        compact ? "w-full" : ""
      }`}
    >
      <span className="mr-2 inline-block h-1.5 w-1.5 rounded-full bg-yield-300 align-middle" />
      {address ? shortAddress(address) : ""}
    </button>
  );
}
