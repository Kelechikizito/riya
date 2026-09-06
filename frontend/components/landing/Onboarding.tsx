import Link from "next/link";
import { Section } from "@/components/ui/Section";

const PREREQS = [
  { label: "An EVM wallet", detail: "MetaMask, Rabby or any injected wallet" },
  { label: "Sepolia ETH", detail: "For the deposit transaction — free from a faucet" },
  { label: "Test USDC", detail: "The asset you are depositing as collateral" },
  { label: "Testnet CTC", detail: "Gas on Creditcoin, for borrowing" },
] as const;

const STEPS = [
  {
    n: 1,
    time: "1 min",
    chain: "Setup",
    side: "neutral",
    title: "Connect and add Creditcoin",
    body: "Hit Connect in the top right. Your wallet will offer to add Creditcoin Testnet if it does not have it. The same address is used on both chains — riya reuses your Ethereum address verbatim on Creditcoin, so there is no second account to manage.",
  },
  {
    n: 2,
    time: "2 min",
    chain: "Ethereum",
    side: "yield",
    title: "Deposit USDC into the escrow",
    body: "Approve the escrow, then deposit. There is a minimum deposit — small deposits cost more in proof gas than they are worth. Once this lands, your collateral is in Aave and earning.",
  },
  {
    n: 3,
    time: "~5 min",
    chain: "Creditcoin",
    side: "credit",
    title: "Wait for the proof to land",
    body: "You do nothing here. A watcher picks up your deposit event, waits for the Ethereum block to be final enough to prove, and submits it to riya's ASC on Creditcoin. Your dashboard flips from pending to credited when the ledger has it.",
  },
  {
    n: 4,
    time: "1 min",
    chain: "Creditcoin",
    side: "credit",
    title: "Borrow rUSD",
    body: "Your opening limit is 10% of collateral. Draw any part of it and rUSD is minted to your address — a plain ERC-20 you can move, hold, or spend anywhere on Creditcoin.",
  },
  {
    n: 5,
    time: "Ongoing",
    chain: "Automatic",
    side: "yield",
    title: "Watch the debt fall",
    body: "Every harvest is proven and applied against your debt. Nothing is asked of you. The dashboard shows the debt, the amount retired so far, and how long the rest will take at the current yield rate.",
  },
] as const;

export function Onboarding() {
  return (
    <Section
      id="start"
      eyebrow="Onboarding guide"
      title="Your first ten minutes"
      lede="Five steps, two chains, and one of them you do nothing for. Everything below is on testnet — no real funds are involved."
    >
      <div className="grid gap-4 lg:grid-cols-[1fr_1.6fr]">
        {/* ------------------------------------------------------ checklist */}
        <aside className="card h-fit p-6 sm:p-7 lg:sticky lg:top-24">
          <p className="eyebrow">Before you start</p>
          <ul className="mt-5 space-y-4">
            {PREREQS.map((p) => (
              <li key={p.label} className="flex gap-3">
                <svg
                  viewBox="0 0 20 20"
                  className="mt-0.5 h-4 w-4 shrink-0 text-yield-300"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M4 10.5l4 4 8-9" />
                </svg>
                <div>
                  <p className="text-sm text-ink">{p.label}</p>
                  <p className="mt-0.5 text-[13px] leading-snug text-faint">
                    {p.detail}
                  </p>
                </div>
              </li>
            ))}
          </ul>
          <Link
            href="/app"
            className="mt-7 inline-flex w-full cursor-pointer items-center justify-center rounded-full bg-yield-300 px-5 py-3 text-sm font-medium text-void transition-colors duration-200 hover:bg-yield-200"
          >
            Start now
          </Link>
          <p className="mt-3 text-center text-[12px] text-faint">
            Takes about ten minutes end to end
          </p>
        </aside>

        {/* ---------------------------------------------------------- steps */}
        <ol className="space-y-4">
          {STEPS.map((s) => {
            const tone =
              s.side === "yield"
                ? "text-yield-300 border-yield-300/25"
                : s.side === "credit"
                  ? "text-credit-400 border-credit-400/25"
                  : "text-muted border-line";
            return (
              <li key={s.n} className="card p-6 sm:p-7">
                <div className="flex flex-wrap items-center gap-3">
                  <span
                    className={`grid h-8 w-8 shrink-0 place-items-center rounded-full border font-mono text-xs ${tone}`}
                  >
                    {s.n}
                  </span>
                  <h3 className="text-lg font-semibold">{s.title}</h3>
                  <span className="ml-auto flex items-center gap-2">
                    <span className="rounded-full border border-line px-2 py-0.5 text-[10px] uppercase tracking-[0.12em] text-faint">
                      {s.chain}
                    </span>
                    <span className="font-mono text-[11px] text-faint">
                      {s.time}
                    </span>
                  </span>
                </div>
                <p className="mt-4 text-[15px] leading-relaxed text-muted sm:pl-11">
                  {s.body}
                </p>
              </li>
            );
          })}
        </ol>
      </div>
    </Section>
  );
}
