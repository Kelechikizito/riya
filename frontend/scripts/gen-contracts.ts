// Regenerates `lib/contracts/abis.ts` and `lib/contracts/addresses.ts`.
//
// Run `forge build` first, then `npm run contracts`. Nothing here is pasted in by hand:
// an ABI copied by hand is one more place for the frontend and the chain to drift apart,
// and an address copied by hand is how a dashboard ends up reading a contract nobody
// deployed. Both come from artefacts the deploy itself produced.
//
// ABIs come from Foundry's `out/`. Addresses come from `deployments/`, written by
// `DeploymentRecord` during the real broadcast.

import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const outDir = join(repo, "out");
const deploymentsDir = join(repo, "deployments");
const targetDir = join(here, "..", "lib", "contracts");

/** Whole ABIs, not slices: the frontend should never have to ask why a method is absent. */
const CONTRACTS: Record<string, string> = {
  LoanLedger: "loanLedgerAbi",
  RiyaASC: "riyaAscAbi",
  RiyaUSD: "riyaUsdAbi",
  RiyaEscrow: "riyaEscrowAbi",
  AaveV4Adapter: "aaveV4AdapterAbi",
  MockUSD: "mockUsdAbi",
  MockAaveSpoke: "mockAaveSpokeAbi",
};

/**
 * How a record's keys become frontend names. Explicit rather than derived, so a renamed
 * variable fails here instead of silently producing `undefined` at the call site.
 */
const ADDRESS_KEYS: Record<string, string> = {
  LOAN_LEDGER_ADDRESS: "loanLedger",
  RIYA_USD_ADDRESS: "riyaUsd",
  RIYA_ASC_ADDRESS: "riyaAsc",
  RIYA_ESCROW_ADDRESS: "escrow",
  AAVE_V4_ADAPTER_ADDRESS: "adapter",
  MOCK_USD: "mockUsd",
  MOCK_SPOKE: "mockSpoke",
  IMPOSTOR_ADDRESS: "impostor",
};

/** Recorded alongside the addresses, and useful to the UI, but not addresses themselves. */
const META_KEYS: Record<string, string> = {
  CHAIN_KEY: "chainKey",
  MOCK_RESERVE_ID: "mockReserveId",
  WORKER_START_BLOCK: "workerStartBlock",
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

const header = (what: string) => `// GENERATED FILE — do not edit.
// Produced by \`npm run contracts\` from ${what}. Regenerate after any contract change
// or redeployment.

`;

// --------------------------------------------------------------------- ABIs
const abiSections = Object.entries(CONTRACTS).map(
  ([contract, exportAs]) =>
    `/** Full ABI of \`${contract}\`. */\nexport const ${exportAs} = ${JSON.stringify(abiOf(contract), null, 2)} as const;`,
);

mkdirSync(targetDir, { recursive: true });
writeFileSync(
  join(targetDir, "abis.ts"),
  header("Foundry's `out/`") + abiSections.join("\n\n") + "\n",
);

// ---------------------------------------------------------------- addresses
type Record_ = Record<string, string | number>;
const byChain = new Map<number, { addresses: Record_; meta: Record_; labels: string[] }>();

for (const file of readdirSync(deploymentsDir).filter((f) => f.endsWith(".json")).sort()) {
  const json = JSON.parse(readFileSync(join(deploymentsDir, file), "utf8")) as Record_;
  const chainId = Number(json.chainId);
  if (!Number.isFinite(chainId)) throw new Error(`${file} has no chainId`);

  const entry = byChain.get(chainId) ?? { addresses: {}, meta: {}, labels: [] };
  entry.labels.push(file.replace(/\.json$/, ""));

  for (const [key, value] of Object.entries(json)) {
    if (key in ADDRESS_KEYS) entry.addresses[ADDRESS_KEYS[key]] = value;
    else if (key in META_KEYS) entry.meta[META_KEYS[key]] = value;
    // chainId/block/deployedAt are per-record bookkeeping and would collide across files.
  }
  byChain.set(chainId, entry);
}

if (byChain.size === 0) throw new Error(`No records in ${deploymentsDir}. Deploy first.`);

const chainEntries = [...byChain.entries()]
  .sort(([a], [b]) => a - b)
  .map(([chainId, { addresses, meta, labels }]) => {
    const body = JSON.stringify({ addresses, meta }, null, 2)
      .split("\n")
      .map((line, i) => (i === 0 ? line : `  ${line}`))
      .join("\n");
    return `  /** From ${labels.join(", ")}. */\n  ${chainId}: ${body},`;
  });

const declared = Object.values(ADDRESS_KEYS)
  .map((n) => `  ${n}?: Address;`)
  .join("\n");

writeFileSync(
  join(targetDir, "addresses.ts"),
  header("`deployments/`") +
    `import type { Address } from "viem";\n\n` +
    `/** The chain each leg of riya runs on, so callers need not hardcode ids. */\n` +
    `export const SOURCE_CHAIN_ID = 11155111 as const;\n` +
    `export const DESTINATION_CHAIN_ID = 102031 as const;\n\n` +
    `/** Every recorded deployment, keyed by chain id. */\n` +
    `export const DEPLOYMENTS = {\n${chainEntries.join("\n")}\n} as const;\n\n` +
    `/** What the app actually reads. Addresses are unique per contract, so flattening\n` +
    ` *  both chains into one object cannot collide, and callers that already know which\n` +
    ` *  contract they want do not have to know which chain it sits on. */\n` +
    `export type Deployed = {\n${declared}\n};\n\n` +
    `export const DEPLOYED: Deployed = {\n` +
    `  ...(DEPLOYMENTS[SOURCE_CHAIN_ID].addresses as Deployed),\n` +
    `  ...(DEPLOYMENTS[DESTINATION_CHAIN_ID].addresses as Deployed),\n` +
    `};\n`,
);

console.log(`Wrote ${join(targetDir, "abis.ts")}`);
console.log(`Wrote ${join(targetDir, "addresses.ts")}`);
