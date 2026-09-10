import { Section } from "@/components/ui/Section";

/**
 * The worked example from the walkthrough, kept in concrete dollars. Ranges and
 * projections read as marketing; one arithmetic story reads as a mechanism.
 */
const STEPS = [
  {
    n: "01",
    side: "yield",
    chain: "Ethereum",
    title: "You deposit $1,000 of USDC",
    body: "It goes into RiyaEscrow, which hands it straight to Aave V4. The escrow keeps no accounting of its own. It emits one event, and that is the entire contract.",
    figure: "$1,000.00",
    figureLabel: "collateral",
  },
  {
    n: "02",
    side: "credit",
    chain: "Creditcoin",
    title: "Your deposit is proven",
    body: "A readability worker notices your deposit and asks Creditcoin to verify it. Creditcoin checks the Ethereum block itself through the Block Prover Precompile.",
    figure: "0x0FD2",
    figureLabel: "precompile",
  },
  {
    n: "03",
    side: "credit",
    chain: "Creditcoin",
    title: "You borrow $100 — 10% to start",
    body: "New addresses open at a 10% limit and mint rUSD against the collateral. The limit is a credit score you have not used yet, increses with your usage of Riya.",
    figure: "$100.00",
    figureLabel: "rUSD minted",
  },
  {
    n: "04",
    side: "yield",
    chain: "Ethereum",
    title: "Your position earns, and is harvested",
    body: "Aave pays roughly 5% a year on the $1,000. Because Aave positions rebase silently, Riya periodically pulls the profit out in a real transaction, turning continuous yield into a discrete, provable fact.",
    figure: "≈ $50",
    figureLabel: "per year",
  },
  {
    n: "05",
    side: "credit",
    chain: "Creditcoin",
    title: "Each harvest retires debt. You pay nothing.",
    body: "The harvest is proven the same way the deposit was. Creditcoin sees real yield arrive and knocks it off your debt. No transaction from you, no repayment schedule, no liquidation price to watch.",
    figure: "−$38.60",
    figureLabel: "debt retired",
  },
  {
    n: "06",
    side: "credit",
    chain: "Creditcoin",
    title: "Your debt reaches zero",
    body: "Then you owe nothing.",
    figure: "$0.00",
    figureLabel: "owed",
  },
] as const;

export function HowItWorks() {
  return (
    <Section
      id="how"
      eyebrow="How it works"
      title="One deposit, six steps, no repayments"
      lede={
        <>
          You have $1,000 USDC and want cash without selling. Here is exactly
          what happens, in the order it happens.
        </>
      }
    >
      <ol className="relative space-y-px">
        {STEPS.map((step, i) => {
          const isYield = step.side === "yield";
          return (
            <li
              key={step.n}
              className={`card group relative overflow-hidden p-6 sm:p-8 ${
                i === 0 ? "rounded-b-none" : ""
              } ${
                i === STEPS.length - 1
                  ? "rounded-t-none"
                  : i === 0
                    ? ""
                    : "rounded-none"
              }`}
            >
              {/* Chain-side accent: the colour tells you which chain you're on
                  before you read the label. */}
              <span
                className={`absolute inset-y-0 left-0 w-px ${
                  isYield ? "bg-yield-300/50" : "bg-credit-400/50"
                }`}
              />

              <div className="grid gap-6 sm:grid-cols-[auto_1fr_auto] sm:items-start sm:gap-8">
                <div className="flex items-center gap-3 sm:block">
                  <span className="font-mono text-xs text-faint">{step.n}</span>
                  <span
                    className={`mt-0 inline-flex items-center gap-1.5 text-[10px] uppercase tracking-[0.14em] sm:mt-2 ${
                      isYield ? "text-yield-300" : "text-credit-400"
                    }`}
                  >
                    <span
                      className={`h-1 w-1 rounded-full ${
                        isYield ? "bg-yield-300" : "bg-credit-400"
                      }`}
                    />
                    {step.chain}
                  </span>
                </div>

                <div className="max-w-xl">
                  <h3 className="text-lg font-semibold sm:text-xl">
                    {step.title}
                  </h3>
                  <p className="mt-3 text-[15px] leading-relaxed text-muted">
                    {step.body}
                  </p>
                </div>

                <div className="sm:text-right">
                  <p
                    className={`font-mono text-xl tabular sm:text-2xl ${
                      isYield ? "text-yield-300" : "text-credit-400"
                    }`}
                  >
                    {step.figure}
                  </p>
                  <p className="mt-1 text-[11px] uppercase tracking-[0.14em] text-faint">
                    {step.figureLabel}
                  </p>
                </div>
              </div>
            </li>
          );
        })}
      </ol>

      <p className="mt-8 text-[15px] leading-relaxed text-muted">
        You never repaid a penny.{" "}
        <span className="text-ink">Your savings did it for you.</span> Your
        savings on one chain and the loan on another.
      </p>
    </Section>
  );
}
