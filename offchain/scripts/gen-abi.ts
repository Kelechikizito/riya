// Regenerates `src/abi.ts` from Foundry's build output.
//
// Run `forge build` first, then `npm run abi`. ABIs are never pasted in by hand: the event
// signatures matter on both sides of the gap (checkpoint 4), and a hand-copied ABI is one
// more place for the two sides to drift apart.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "..", "..", "out");
const target = join(here, "..", "src", "abi.ts");

/** Only the fragments the off-chain programs actually call or listen for. */
const WANTED: Record<string, { exportAs: string; fragments: string[] }> = {
  RiyaASC: {
    exportAs: "RIYA_ASC_ABI",
    // The error fragments matter as much as the functions: with them in the ABI, ethers
    // decodes a reverted `submit` into `RiyaASC__NoRelevantLog` rather than an opaque
    // selector, which is what lets the worker tell permanent failures from retriable ones.
    fragments: [
      "submit",
      "isConsumed",
      "I_CHAIN_KEY",
      "ProofConsumed",
      "RiyaASC__AlreadyConsumed",
      "RiyaASC__NoRelevantLog",
      "RiyaASC__ProofInvalid",
      "RiyaASC__TxReverted",
      "RiyaASC__ZeroHeight",
    ],
  },
  RiyaEscrow: {
    exportAs: "RIYA_ESCROW_ABI",
    fragments: ["TokensDepositedConfirmedByEscrow"],
  },
  AaveV4Adapter: {
    exportAs: "AAVE_V4_ADAPTER_ABI",
    fragments: ["TokensHarvested", "yieldAccrued", "harvest", "I_MIN_HARVEST"],
  },
};

type Fragment = { type: string; name?: string };

function abiOf(contract: string): Fragment[] {
  const path = join(outDir, `${contract}.sol`, `${contract}.json`);
  try {
    return JSON.parse(readFileSync(path, "utf8")).abi as Fragment[];
  } catch {
    throw new Error(`Could not read ${path}. Run \`forge build\` first.`);
  }
}

const sections: string[] = [];

for (const [contract, { exportAs, fragments }] of Object.entries(WANTED)) {
  const abi = abiOf(contract);
  const picked = abi.filter((f) => f.name !== undefined && fragments.includes(f.name));

  const missing = fragments.filter((n) => !picked.some((f) => f.name === n));
  if (missing.length > 0) {
    throw new Error(`${contract} is missing: ${missing.join(", ")}. Did the contract change?`);
  }

  sections.push(`export const ${exportAs} = ${JSON.stringify(picked, null, 2)} as const;`);
}

const header = `// GENERATED FILE — do not edit.
// Produced by \`npm run abi\` from Foundry's \`out/\`. Regenerate after any contract change.

`;

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, header + sections.join("\n\n") + "\n");
console.log(`Wrote ${target}`);
