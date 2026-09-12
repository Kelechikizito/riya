"use client";

import { useId, useState } from "react";
import { Section } from "@/components/ui/Section";
import { SCORE_TIERS, tierForScore } from "@/lib/score";

const COLLATERAL = 1_000;
/** The ladder tops out when yield has retired 20% of collateral. */
const GRADUATION_TARGET = 0.2;

export function CreditLadder() {
  const sliderId = useId();
  const [retired, setRetired] = useState(38.6);

  const score = Math.min(
    100,
    Math.floor((retired / (COLLATERAL * GRADUATION_TARGET)) * 100),
  );
  const tier = tierForScore(score);
  const limit = (COLLATERAL * tier.ltvBps) / 10_000;

  return (
    <Section
      id="credit"
      eyebrow="Credit score"
      title="A limit you earn"
      lede="Your borrow limit starts at 10% and climbs to 50%. It moves for one reason: yield retiring your debt. Cash repayments do not count."
    >
      <div className="grid gap-4 lg:grid-cols-[1.1fr_1fr]">
        {/* ------------------------------------------------- interactive dial */}
        <div className="card p-6 sm:p-8">
          <p className="eyebrow">Try it</p>
          <label
            htmlFor={sliderId}
            className="mt-3 block text-[15px] leading-relaxed font-bold"
          >
            On $1,000 of collateral, drag to change how much debt your{" "}
            <span className="text-yield-300">yield</span> has retired.
          </label>

          <div className="mt-7 flex items-baseline gap-3">
            <span className="font-mono text-4xl tabular text-yield-300">
              ${retired.toFixed(2)}
            </span>
            <span className="text-sm text-faint">retired by yield</span>
          </div>

          <input
            id={sliderId}
            type="range"
            min={0}
            max={220}
            step={0.2}
            value={retired}
            onChange={(e) => setRetired(Number(e.target.value))}
            aria-valuetext={`$${retired.toFixed(2)} retired by yield, score ${score}, limit ${tier.ltvBps / 100}%`}
            className="mt-6 h-11 w-full cursor-pointer accent-[#5eead4]"
          />

          <div className="mt-6 grid grid-cols-3 gap-4 border-t border-line pt-6">
            <Stat label="Score" value={String(score)} tone="credit" />
            <Stat
              label="Max LTV"
              value={`${tier.ltvBps / 100}%`}
              tone="credit"
            />
            <Stat
              label="You may borrow"
              value={`$${limit.toLocaleString("en-US")}`}
              tone="ink"
            />
          </div>

          <p className="mt-6 text-[13px] leading-relaxed text-faint">
            The credit score is relative to your <em>cumulative</em> debt
            retired.
          </p>
        </div>

        {/* ----------------------------------------------------- the ladder */}
        <div className="card overflow-hidden p-6 sm:p-8">
          <p className="eyebrow">The ladder</p>
          <ul className="mt-6 space-y-1">
            {SCORE_TIERS.map((t) => {
              const active = t.min === tier.min;
              return (
                <li
                  key={t.min}
                  className={`flex items-center gap-4 rounded-lg px-3 py-3 transition-colors duration-300 ${
                    active ? "bg-credit-400/10" : ""
                  }`}
                >
                  <span
                    className={`w-16 shrink-0 font-mono text-xs tabular ${
                      active ? "text-credit-400" : "text-faint"
                    }`}
                  >
                    {t.min}–{t.max === 100 ? "100" : t.max}
                  </span>
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-line">
                    <div
                      className={`h-full rounded-full transition-colors duration-300 ${
                        active ? "bg-credit-400" : "bg-line-soft"
                      }`}
                      style={{ width: `${(t.ltvBps / 5_000) * 100}%` }}
                    />
                  </div>
                  <span
                    className={`w-12 shrink-0 text-right font-mono text-sm tabular ${
                      active ? "text-ink" : "text-faint"
                    }`}
                  >
                    {t.ltvBps / 100}%
                  </span>
                </li>
              );
            })}
          </ul>

          <div className="mt-7 border-t border-line pt-6">
            <h3 className="text-[15px] font-semibold">
              Why cash repayment does not count
            </h3>
            <p className="mt-3 text-[14px] leading-relaxed text-muted">
              If repaying moved the score, anyone could borrow $100 and repay
              $100 on a loop without their collateral ever doing any work. Only
              proven yield writes to the score, so the ladder measures
              productive collateral.
            </p>
          </div>
        </div>
      </div>
    </Section>
  );
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string;
  value: string;
  tone: "ink" | "credit";
}) {
  return (
    <div>
      <p
        className={`font-mono text-2xl tabular ${
          tone === "credit" ? "text-credit-400" : "text-ink"
        }`}
      >
        {value}
      </p>
      <p className="mt-1.5 text-[11px] uppercase tracking-[0.14em] text-faint">
        {label}
      </p>
    </div>
  );
}
