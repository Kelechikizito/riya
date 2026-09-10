import { Section } from "@/components/ui/Section";

const PHASES = [
  {
    phase: "Phase 0",
    status: "shipped",
    horizon: "Hackathon submission",
    title: "The vertical slice",
    body: "One asset, one source chain, one destination. USDC on Ethereum Sepolia into Aave V4, harvests proven onto Creditcoin Testnet, rUSD minted against a credit score that only proven yield can increase.",
    items: [
      "RiyaEscrow + AaveV4Adapter on Ethereum",
      "RiyaASC proof verification with receiptStatus and per-event address pinning",
      "LoanLedger: collateral, fee, score, LTV, debt",
      "rUSD as a spendable ERC-20 on Creditcoin",
    ],
  },
  {
    phase: "Phase 1",
    status: "next",
    horizon: "Post-hackathon",
    title: "Harden and open",
    body: "Everything needed before anyone's real money is welcome.",
    items: [
      "External audits",
      "Batched harvests tuned to Ethereum mainnet gas.",
      "Proven impairment marks, so an Aave loss prices into collateral and stops backing new borrowing instead of accruing silently",
      "Permissionless readability watchers, so no single operator can stall proofs",
      "More collateral assets and additional yield adapters behind IYieldAdapter",
    ],
  },
  {
    phase: "Phase 2",
    status: "planned",
    horizon: "Ecosystem",
    title: "Make rUSD worth holding",
    body: "his phase is about the Creditcoin side of the ledger becoming valuable.",
    items: [
      "rUSD liquidity on Creditcoin DEXes",
      "Riya's credit score exposed as a public read-only other Creditcoin protocols can price against",
      "Delegated borrowing, lend your unused limit to an address you trust",
      "Merchant and payment rails for rUSD",
    ],
  },
  {
    phase: "Phase 3",
    status: "gated",
    horizon: "Blocked on protocol capability",
    title: "The return leg, Attestcoin writability",
    body: "These need Creditcoin features that are not released yet.",
    items: [
      "Collateral release back to Ethereum, needs writability, currently in third-party audit",
      "Additional source chains asides Ethereum Mainnet",
      "Cross-chain liquidation-free refinancing between destinations",
    ],
  },
] as const;

const STATUS_STYLE = {
  shipped: { dot: "bg-yield-300", text: "text-yield-300", label: "Built" },
  next: { dot: "bg-credit-400", text: "text-credit-400", label: "Next" },
  planned: { dot: "bg-muted", text: "text-muted", label: "Planned" },
  gated: { dot: "bg-line", text: "text-faint", label: "Gated" },
} as const;

export function Roadmap() {
  return (
    <Section
      id="roadmap"
      eyebrow="Roadmap"
      title="Where this goes next"
      lede="Phases 0 through 2 are ours to execute. Phase 3 is not."
    >
      <div className="relative">
        {/* The spine. Hidden on mobile, where the cards stack anyway. */}
        <span
          aria-hidden="true"
          className="absolute left-[7px] top-2 hidden h-[calc(100%-1rem)] w-px bg-gradient-to-b from-yield-300/50 via-credit-400/30 to-transparent sm:block"
        />

        <ol className="space-y-4">
          {PHASES.map((p) => {
            const style = STATUS_STYLE[p.status];
            return (
              <li key={p.phase} className="relative sm:pl-10">
                <span
                  aria-hidden="true"
                  className={`absolute left-0 top-7 hidden h-3.5 w-3.5 rounded-full border-4 border-void sm:block ${style.dot}`}
                />
                <article
                  className={`card p-6 sm:p-8 ${
                    p.status === "gated" ? "border-dashed" : ""
                  }`}
                >
                  <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
                    <span className="font-mono text-xs text-faint">
                      {p.phase}
                    </span>
                    <span
                      className={`inline-flex items-center gap-1.5 rounded-full border border-line px-2.5 py-0.5 text-[10px] uppercase tracking-[0.14em] ${style.text}`}
                    >
                      <span className={`h-1 w-1 rounded-full ${style.dot}`} />
                      {style.label}
                    </span>
                    <span className="text-[12px] text-faint">{p.horizon}</span>
                  </div>

                  <h3 className="mt-4 text-xl font-semibold">{p.title}</h3>
                  <p className="mt-3 max-w-2xl text-[15px] leading-relaxed text-muted">
                    {p.body}
                  </p>

                  <ul className="mt-6 grid gap-3 sm:grid-cols-2">
                    {p.items.map((item) => (
                      <li key={item} className="flex gap-2.5">
                        <span
                          aria-hidden="true"
                          className={`mt-2 h-1 w-1 shrink-0 rounded-full ${style.dot}`}
                        />
                        <span className="text-[14px] leading-relaxed text-muted">
                          {item}
                        </span>
                      </li>
                    ))}
                  </ul>
                </article>
              </li>
            );
          })}
        </ol>
      </div>
    </Section>
  );
}
