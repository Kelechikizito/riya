import { Section } from "@/components/ui/Section";

type Risk = {
  title: string;
  body: string;
  /** The designed response, where there is one. Absent means we are still only naming it. */
  answer?: string;
};

const RISKS: readonly Risk[] = [
  {
    title: "If Aave is impaired, Riya absorbs it",
    body: "Yield is measured as what Aave holds minus what we put in. If that reserve takes a loss, the collateral shrinks while the Creditcoin debt does not. Riya has no liquidation path at all, so the protocol wears the gap rather than the borrower.",
    answer:
      "Designed, not built. A shortfall is provable the same way yield is: the adapter marks holdings against principal on Ethereum, and Creditcoin verifies that mark through the same precompile. The fee accrued so far absorbs it, the remainder spreads across collateral, and impaired collateral stops backing new borrowing. That prices a loss the moment it is proven. It does not refund one.",
  },
  {
    title: "Proofs are not instant",
    body: "A deposit is credited once its Ethereum block is final enough to prove, not the moment it lands. Expect minutes, not seconds.",
  },
  {
    title: "This is unaudited testnet software",
    body: "Built inside a hackathon window. It has fork tests on the Ethereum contracts and no external audit on either. An audit is the first item in Phase 1 for exactly this reason. Do not put anything you cannot lose in front of it.",
  },
];

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
            {r.answer ? (
              <div className="mt-5 border-t border-line pt-4">
                <p className="eyebrow">What we do about it</p>
                <p className="mt-2 text-[14px] leading-relaxed text-faint">
                  {r.answer}
                </p>
              </div>
            ) : null}
          </article>
        ))}
      </div>
    </Section>
  );
}
