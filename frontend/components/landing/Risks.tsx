import { Section } from "@/components/ui/Section";

const RISKS = [
  {
    title: "If Aave is impaired, riya absorbs it",
    body: "Yield is measured as what Aave holds minus what we put in. If that reserve takes a loss, the collateral shrinks while the Creditcoin debt does not. Riya has no liquidation path at all, so the protocol wears the gap rather than the borrower. This is riya's real risk and we would rather name it than have you find it.",
  },
  {
    title: "Proofs are not instant",
    body: "A deposit is credited once its Ethereum block is final enough to prove, not the moment it lands. Expect minutes, not seconds. On mainnet, harvests are deliberately batched — fewer, larger proofs — because Ethereum gas is a real cost and the only honest lever against it is frequency.",
  },
  {
    title: "This is unaudited testnet software",
    body: "Built inside a hackathon window. It has fork tests on the the Ethereum contracts and no external audit on either. An audit is the first item in Phase 1 for exactly this reason. Do not put anything you cannot lose in front of it.",
  },
] as const;

export function Risks() {
  return (
    <Section
      id="risk"
      eyebrow="Risks"
      title="What can go wrong"
      lede="A risk you find on your own discounts everything else on the page. Here are ours, first."
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {RISKS.map((r) => (
          <article key={r.title} className="card p-6 sm:p-7">
            <div className="flex items-start gap-3">
              <svg
                viewBox="0 0 24 24"
                className="mt-0.5 h-5 w-5 shrink-0 text-credit-400"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M12 4.5l8.5 15h-17l8.5-15z" />
                <path d="M12 10v4.5M12 17.2v.1" />
              </svg>
              <h3 className="text-lg font-semibold">{r.title}</h3>
            </div>
            <p className="mt-3 text-[15px] leading-relaxed text-muted">
              {r.body}
            </p>
          </article>
        ))}
      </div>
    </Section>
  );
}
