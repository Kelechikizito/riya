import { defineChain } from "viem";

/**
 * Creditcoin's EVM testnet — riya's destination chain, where every decision
 * (collateral, fee, credit score, LTV, debt) actually lives.
 *
 * RPC and explorer are env-overridable because these endpoints move around
 * more than mainnet ones do.
 */
export const creditcoinTestnet = defineChain({
  id: 102031,
  name: "Creditcoin Testnet",
  nativeCurrency: { name: "Creditcoin", symbol: "tCTC", decimals: 18 },
  rpcUrls: {
    default: {
      http: [
        process.env.NEXT_PUBLIC_CREDITCOIN_RPC_URL ??
          "https://rpc.cc3-testnet.creditcoin.network",
      ],
    },
  },
  blockExplorers: {
    default: {
      name: "Blockscout",
      url:
        process.env.NEXT_PUBLIC_CREDITCOIN_EXPLORER_URL ??
        "https://creditcoin-testnet.blockscout.com",
    },
  },
  testnet: true,
});

/** Where a user's collateral physically sits. Read-only from riya's UI. */
export const SOURCE_CHAIN = {
  id: 11155111,
  name: "Ethereum Sepolia",
  explorer: "https://sepolia.etherscan.io",
} as const;

/**
 * Attestcoin's Block Prover Precompile. Hardcoded on every Creditcoin network;
 * quoted on the site because naming the primitive is the whole alignment claim.
 */
export const BLOCK_PROVER_PRECOMPILE = "0x0FD2" as const;

/**
 * Attestcoin's per-network chain keys. Creditcoin testnet numbers Sepolia as 1
 * and Ethereum mainnet as 3; Creditcoin mainnet numbers Ethereum mainnet as 1.
 */
export const CHAIN_KEYS = {
  creditcoinTestnet: { sepolia: 1, ethereumMainnet: 3 },
  creditcoinMainnet: { ethereumMainnet: 1 },
} as const;
