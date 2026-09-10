import Link from "next/link";
import { Section } from "@/components/ui/Section";

const DOCS = [
  {
    title: "Protocol walkthrough",
    body: "Eight checkpoints, contract by contract, with the reasoning behind each decision rather than just the code.",
    meta: "8 checkpoints",
  },
  {
    title: "Contract reference",
    body: "Deployed addresses, ABIs, events, and the exact proof format RiyaASC accepts.",
    meta: "Sepolia + Creditcoin Testnet",
  },
  {
    title: "Integrating rUSD",
    body: "How to accept rUSD in a Creditcoin contract, and how to read a riya credit score from your own protocol.",
    meta: "For builders",
  },
] as const;

export function DocsCta() {
  return (
    <Section id="docs">
      <div className="card relative overflow-hidden p-8 sm:p-12">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-yield-500/15 blur-[100px]"
        />
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -bottom-32 left-1/3 h-72 w-72 rounded-full bg-credit-600/12 blur-[110px]"
        />

        <div className="relative max-w-2xl">
          <p className="eyebrow">Documentation</p>
          <h2 className="mt-4 text-[1.75rem] font-semibold leading-[1.15] sm:text-[2.25rem]">
            Read the whole thing
          </h2>
          <p className="mt-5 text-[17px] leading-relaxed text-muted">
            Every claim on this page traces back to a contract you can read. The
            docs are being assembled from the build walkthrough now.
          </p>
        </div>

        <div className="relative mt-10 grid gap-4 sm:grid-cols-3">
          {DOCS.map((d) => (
            <div
              key={d.title}
              className="rounded-xl border border-line bg-raised/50 p-5"
            >
              <h3 className="text-[15px] font-semibold">{d.title}</h3>
              <p className="mt-2.5 text-[13px] leading-relaxed text-muted">
                {d.body}
              </p>
              <p className="mt-4 font-mono text-[11px] text-faint">{d.meta}</p>
            </div>
          ))}
        </div>

        <div className="relative mt-10 flex flex-wrap items-center gap-3">
          <Link
            href="/docs"
            className="cursor-pointer rounded-full bg-yield-300 px-6 py-3 text-[15px] font-medium text-void transition-colors duration-200 hover:bg-yield-200"
          >
            Open the docs
          </Link>
        </div>
      </div>
    </Section>
  );
}
