// GENERATED FILE — do not edit.
// Produced by `npm run contracts` from `deployments/`. Regenerate after any contract change
// or redeployment.

import type { Address } from "viem";

/** The chain each leg of riya runs on, so callers need not hardcode ids. */
export const SOURCE_CHAIN_ID = 11155111 as const;
export const DESTINATION_CHAIN_ID = 102031 as const;

/** Every recorded deployment, keyed by chain id. */
export const DEPLOYMENTS = {
  /** From 102031-destination. */
  102031: {
    "addresses": {
      "loanLedger": "0x551904f44630B7C2ac9BBf81db795928Cc329E86",
      "riyaAsc": "0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7",
      "riyaUsd": "0x194b050678eb50923b84fE5aDC8E6f8176D43335"
    },
    "meta": {
      "chainKey": 1
    }
  },
  /** From 11155111-mocks, 11155111-source. */
  11155111: {
    "addresses": {
      "mockSpoke": "0xf0f1ea77A624382C3656aE5C4d93dBfEC59e3064",
      "mockUsd": "0xcA1BA8049f1e29c07f539C7c918dcc1D57BF318F",
      "adapter": "0x83142d63752E09490c4FfCd2482568a7c8618bFb",
      "escrow": "0xEDe17e550D36597CA497356DBE2CfCebC876b72e"
    },
    "meta": {
      "mockReserveId": 1,
      "workerStartBlock": 11680869
    }
  },
} as const;

/** What the app actually reads. Addresses are unique per contract, so flattening
 *  both chains into one object cannot collide, and callers that already know which
 *  contract they want do not have to know which chain it sits on. */
export type Deployed = {
  loanLedger?: Address;
  riyaUsd?: Address;
  riyaAsc?: Address;
  escrow?: Address;
  adapter?: Address;
  mockUsd?: Address;
  mockSpoke?: Address;
  impostor?: Address;
};

export const DEPLOYED: Deployed = {
  ...(DEPLOYMENTS[SOURCE_CHAIN_ID].addresses as Deployed),
  ...(DEPLOYMENTS[DESTINATION_CHAIN_ID].addresses as Deployed),
};
