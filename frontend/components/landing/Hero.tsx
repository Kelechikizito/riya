import Link from "next/link";
import { Aurora } from "@/components/ui/Aurora";
import { FlowDiagram } from "./FlowDiagram";

const FACTS = [
  { value: "$0", label: "Repayments you make", tone: "yield" },
  { value: "Never", label: "Liquidation events", tone: "yield" },
  { value: "10 → 50%", label: "Borrow limit, earned", tone: "credit" },
  { value: "1", label: "Proof crosses. Nothing else", tone: "credit" },
] as const;

export function Hero() {
  return (
    <div className="relative isolate">
      <Aurora />

      <div className="mx-auto max-w-6xl px-5 pb-20 pt-16 sm:px-8 sm:pb-28 sm:pt-24">
        <div className="max-w-3xl">
          <span className="inline-flex items-center gap-2 rounded-full border border-line bg-surface/60 px-3 py-1.5 text-xs text-muted backdrop-blur">
            <span className="h-1.5 w-1.5 animate-pulse-soft rounded-full bg-yield-300" />
            Built on Creditcoin with Attestcoin readability
          </span>

          <h1 className="mt-7 text-[2.5rem] font-semibold leading-[1.02] tracking-[-0.03em] sm:text-[4rem] lg:text-[4.75rem]">
            You never make
            <br />
            <span className="duotone-text">a repayment.</span>
          </h1>

          <p className="mt-7 max-w-xl text-[17px] leading-relaxed text-muted sm:text-[19px]">
            With no bridge or oracle, put USDC to work on Aave V4 (Ethereum).
            Borrow against it on Creditcoin. The yield your deposit earns is
            proven across and quietly retires the debt, until you owe nothing.
          </p>

          <p className="mt-4 max-w-xl text-[15px] leading-relaxed text-faint">
            Your savings make the payments. You wait and do nothing.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-3">
            <Link
              href="/app"
              className="cursor-pointer rounded-full bg-yield-300 px-6 py-3 text-[15px] font-medium text-void transition-colors duration-200 hover:bg-yield-200"
            >
              Open the app
            </Link>
            <Link
              href="#how"
              className="cursor-pointer rounded-full border border-line px-6 py-3 text-[15px] text-ink transition-colors duration-200 hover:border-muted hover:bg-surface"
            >
              See how it works
            </Link>
          </div>
        </div>

        <div className="mt-16 sm:mt-20">
          <FlowDiagram />
        </div>

        <dl className="mt-10 grid grid-cols-2 gap-x-6 gap-y-8 border-t border-line pt-10 lg:grid-cols-4">
          {FACTS.map((fact) => (
            <div key={fact.label}>
              <dt className="sr-only">{fact.label}</dt>
              <dd
                className={`font-mono text-2xl tabular sm:text-[1.75rem] ${
                  fact.tone === "yield" ? "text-yield-300" : "text-credit-400"
                }`}
              >
                {fact.value}
              </dd>
              <p className="mt-2 text-[13px] leading-snug text-muted">
                {fact.label}
              </p>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}
