import type { Metadata } from "next";
import Link from "next/link";
import { SiteNav } from "@/components/site/SiteNav";
import { SiteFooter } from "@/components/site/SiteFooter";
import { BLOCK_PROVER_PRECOMPILE } from "@/lib/chains";

export const metadata: Metadata = {
  title: "Documentation",
  description:
    "riya protocol documentation — contracts, proof format, and integration guides. In progress.",
};

/**
 * Deliberately a stub, and labelled as one. Each entry names what it will
 * contain and where that content already exists in the repo, so the page is
 * useful to a reader today rather than being an empty promise.
 */
const SECTIONS = [
  {
    group: "Protocol",
    entries: [
      {
        title: "The one-sentence pitch",
        body: "What riya does, in dollars, with a worked example.",
        source: "walkthrough/01-aave-v4-adapter.md",
        ready: true,
      },
      {
        title: "How value and proofs move",
        body: "The full path from a USDC deposit on Ethereum to a debt decrement on Creditcoin.",
        source: "research/how-value-and-proofs-move.md",
        ready: true,
      },
      {
        title: "Build plan",
        body: "How the system is put together, in build order.",
        source: "research/build-plan.md",
        ready: true,
      },
    ],
  },
  {
    group: "Contracts",
    entries: [
      {
        title: "RiyaEscrow",
        body: "Custody only. One function, one event, no mutable state.",
        source: "walkthrough/03-riya-escrow.md",
        ready: true,
      },
      {
        title: "AaveV4Adapter",
        body: "Turns Aave's silently-rebasing balance into discrete, provable harvest events.",
        source: "walkthrough/01-aave-v4-adapter.md",
        ready: true,
      },
      {
        title: "RiyaASC",
        body: "Proof verification: receipt status, per-event address pinning, replay protection.",
        source: "walkthrough/06-riya-asc.md",
        ready: true,
      },
      {
        title: "LoanLedger",
        body: "Collateral, protocol fee, yield accumulator, credit score, LTV ladder, debt.",
        source: "walkthrough/08-loan-ledger.md",
        ready: true,
      },
      {
        title: "RiyaUSD",
        body: "The borrowable dollar. Six decimals, mint and burn gated to the ledger.",
        source: "walkthrough/07-riya-usd.md",
        ready: true,
      },
    ],
  },
  {
    group: "Integrating",
    entries: [
      {
        title: "Deployed addresses",
        body: "Sepolia and Creditcoin Testnet addresses, with verified source links.",
        source: "Pending deployment",
        ready: false,
      },
      {
        title: "Accepting rUSD",
        body: "Adding rUSD to a Creditcoin contract, wallet or pool.",
        source: "Not written yet",
        ready: false,
      },
      {
        title: "Reading a riya credit score",
        body: "Using riya's on-chain score as a signal in your own protocol.",
        source: "Not written yet",
        ready: false,
      },
    ],
  },
] as const;

export default function DocsPage() {
  return (
    <>
      <SiteNav />
      <main className="flex-1">
        <div className="mx-auto max-w-4xl px-5 py-20 sm:px-8 sm:py-28">
          <p className="eyebrow">Documentation</p>
          <h1 className="mt-4 text-[2.25rem] font-semibold leading-[1.08] sm:text-[3rem]">
            Docs are being assembled
          </h1>
          <p className="mt-6 max-w-2xl text-[17px] leading-relaxed text-muted sm:text-[19px]">
            The protocol is documented in full inside the repository — eight
            build checkpoints written to be read cold. This page is where that
            material is being published, section by section. Nothing below is a
            placeholder for work that has not happened; the entries marked{" "}
            <span className="text-yield-300">written</span> already exist in the
            repo today.
          </p>

          <div className="card mt-10 flex flex-wrap items-center gap-x-8 gap-y-4 p-6">
            <Meta label="Precompile" value={BLOCK_PROVER_PRECOMPILE} />
            <Meta label="Source chain" value="Ethereum Sepolia" />
            <Meta label="Destination" value="Creditcoin Testnet" />
            <Meta label="Token" value="rUSD · 6 decimals" />
          </div>

          <div className="mt-16 space-y-14">
            {SECTIONS.map((section) => (
              <section key={section.group}>
                <h2 className="text-xl font-semibold">{section.group}</h2>
                <ul className="mt-6 space-y-px">
                  {section.entries.map((entry) => (
                    <li
                      key={entry.title}
                      className="card flex flex-col gap-3 p-5 sm:flex-row sm:items-center sm:justify-between sm:gap-6"
                    >
                      <div className="max-w-xl">
                        <h3 className="text-[15px] font-semibold">
                          {entry.title}
                        </h3>
                        <p className="mt-1.5 text-[14px] leading-relaxed text-muted">
                          {entry.body}
                        </p>
                      </div>
                      <div className="shrink-0 sm:text-right">
                        <span
                          className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[10px] uppercase tracking-[0.14em] ${
                            entry.ready
                              ? "border-yield-300/30 text-yield-300"
                              : "border-line text-faint"
                          }`}
                        >
                          <span
                            className={`h-1 w-1 rounded-full ${
                              entry.ready ? "bg-yield-300" : "bg-line"
                            }`}
                          />
                          {entry.ready ? "Written" : "Planned"}
                        </span>
                        <p className="mt-2 font-mono text-[11px] text-faint">
                          {entry.source}
                        </p>
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </div>

          <div className="card mt-16 p-6 sm:p-8">
            <h2 className="text-lg font-semibold">In the meantime</h2>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              The landing page explains the mechanism end to end, and the
              dashboard shows the position it produces.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
              <Link
                href="/#how"
                className="cursor-pointer rounded-full border border-line px-5 py-2.5 text-sm text-ink transition-colors hover:border-muted hover:bg-surface"
              >
                How it works
              </Link>
              <Link
                href="/app"
                className="cursor-pointer rounded-full bg-yield-300 px-5 py-2.5 text-sm font-medium text-void transition-colors hover:bg-yield-200"
              >
                Open the app
              </Link>
            </div>
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] uppercase tracking-[0.14em] text-faint">
        {label}
      </p>
      <p className="mt-1 font-mono text-sm text-ink">{value}</p>
    </div>
  );
}
