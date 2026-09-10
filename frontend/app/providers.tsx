"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { creditcoinTestnet } from "@/lib/chains";

/**
 * Plain wagmi with the injected connector — MetaMask, Rabby, Brave, Frame.
 *
 * RainbowKit was the obvious choice here and is deliberately not used: it
 * bundles a Base Account connector that pulls @coinbase/cdp-sdk and its
 * optional Solana packages, which break the build and add several hundred
 * transitive dependencies riya never executes. The connect UI is small enough
 * to own, and owning it means it matches the palette.
 *
 * Both chains are configured because riya is genuinely two-sided: the deposit is an
 * Ethereum transaction and everything after it is a Creditcoin one. Creditcoin is listed
 * first, which makes it the default the dashboard reads from; the deposit panel asks the
 * wallet to switch and switches it back.
 */
const config = createConfig({
  chains: [creditcoinTestnet, sepolia],
  connectors: [injected()],
  transports: {
    [creditcoinTestnet.id]: http(),
    [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
  },
  ssr: true,
});

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
