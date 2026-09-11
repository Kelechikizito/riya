import { Section } from "@/components/ui/Section";
import { BLOCK_PROVER_PRECOMPILE, SOURCE_CHAIN, creditcoinTestnet } from "@/lib/chains";
import { ADDRESSES } from "@/lib/contracts";
import { shortAddress } from "@/lib/format";

type Entry = {
  name: string;
  address?: string;
  /** Absent for the precompiles, which are native node code with no explorer page. */
  explorer?: string;
  /** One line on what it is. Shown under the name. */
  note: string;
};

const CHAIN_INFO_PRECOMPILE = "0x0FD3";

const creditcoin: readonly Entry[] = [
  {
    name: "LoanLedger",
    address: ADDRESSES.loanLedger,
    note: "Collateral, debt, credit score, borrow limit",
  },
  {
    name: "RiyaASC",
    address: ADDRESSES.riyaAsc,
    note: "Verifies Ethereum proofs. The only door between the chains",
  },
  {
    name: "RiyaUSD",
    address: ADDRESSES.riyaUsd,
    note: "The borrowable dollar. 6 decimals, minted only by the ledger",
  },
];

const sepolia: readonly Entry[] = [
  {
    name: "RiyaEscrow",
    address: ADDRESSES.escrow,
    note: "Custody. Emits the deposit event Creditcoin proves",
  },
  {
    name: "AaveV4Adapter",
    address: ADDRESSES.adapter,
    note: "Supplies to Aave and harvests yield back to the escrow",
  },
  {
    name: "MockUSD",
    address: ADDRESSES.mockUsd,
    note: "Demo dollar. Aave V4 is mainnet-only, so testnet needs a stand-in",
  },
];

const precompiles: readonly Entry[] = [
  {
    name: "BlockProver",
    address: BLOCK_PROVER_PRECOMPILE,
    note: "Verifies that an Ethereum transaction really happened",
  },
  {
    name: "ChainInfo",
    address: CHAIN_INFO_PRECOMPILE,
    note: "Names the source chains this network can read",
  },
];

/**
 * The addresses, so a stranger can check the claims rather than take them.
 *
 * Every address is read from the environment at build time, which means this section is
 * either correct or visibly empty. There is no hardcoded fallback, because a stale address
 * that looks live is worse than an honest gap.
 */
export function Deployed() {
  return (
    <Section
      id="deployed"
      eyebrow="Live"
      title="What is deployed"
      lede="Live contracts on two chains, and the Attestcoin precompiles they depend on. Every one is verifiable without trusting a word on this page."
    >
      <div className="grid gap-x-12 gap-y-10 lg:grid-cols-2">
        <Column
          title="Creditcoin Testnet"
          subtitle="Where every decision is made"
          entries={creditcoin}
          explorer={creditcoinTestnet.blockExplorers.default.url}
        />

        <div className="flex flex-col gap-10">
          <Column
            title="Ethereum Sepolia"
            subtitle="Where the money sits, earning"
            entries={sepolia}
            explorer={SOURCE_CHAIN.explorer}
          />
          <Column
            title="Attestcoin precompiles"
            subtitle="Native to Creditcoin. Not deployed by riya"
            entries={precompiles}
          />
        </div>
      </div>
    </Section>
  );
}

function Column({
  title,
  subtitle,
  entries,
  explorer,
}: {
  title: string;
  subtitle: string;
  entries: readonly Entry[];
  explorer?: string;
}) {
  return (
    <div>
      <div className="border-b border-line pb-3">
        <h3 className="text-[15px] font-semibold">{title}</h3>
        <p className="mt-1 text-[13px] text-faint">{subtitle}</p>
      </div>

      <ul>
        {entries.map((entry) => (
          <li
            key={entry.name}
            className="flex items-baseline justify-between gap-6 border-b border-line py-4"
          >
            <div className="min-w-0">
              <p className="text-[15px] text-ink">{entry.name}</p>
              <p className="mt-1 text-[13px] leading-relaxed text-faint">{entry.note}</p>
            </div>
            <AddressCell address={entry.address} explorer={explorer} />
          </li>
        ))}
      </ul>
    </div>
  );
}

function AddressCell({ address, explorer }: { address?: string; explorer?: string }) {
  if (!address) {
    return (
      <span className="shrink-0 font-mono text-[13px] text-faint" title="Not yet deployed">
        not deployed
      </span>
    );
  }

  // Precompiles get no link. They are native node code, so an explorer has no page for
  // them, and a link that 404s reads as a broken claim.
  if (!explorer) {
    return <span className="shrink-0 font-mono text-[13px] text-muted">{address}</span>;
  }

  return (
    <a
      href={`${explorer}/address/${address}`}
      target="_blank"
      rel="noreferrer"
      title={address}
      className="shrink-0 font-mono text-[13px] text-muted underline decoration-line decoration-dotted underline-offset-4 transition-colors duration-200 hover:text-yield-300 hover:decoration-yield-300"
    >
      {shortAddress(address)}
    </a>
  );
}
