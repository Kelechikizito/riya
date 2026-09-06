"use client";

import { useEffect, useState } from "react";
import { usePrefersReducedMotion } from "@/lib/hydration";

/**
 * The four beats of riya, on a loop.
 *
 * This is the hero's whole job: show that the money never leaves Ethereum, the
 * debt never leaves Creditcoin, and the only thing that crosses is a proof.
 * That distinction is what stops riya being a vault that could ship on any L2.
 */
const STEPS = [
  { key: "deposit", label: "Deposit", caption: "USDC into RiyaEscrow, supplied to Aave V4" },
  { key: "accrue", label: "Accrue", caption: "The position earns. Nothing to prove yet" },
  { key: "prove", label: "Prove", caption: "Harvest verified on Creditcoin via 0x0FD2" },
  { key: "retire", label: "Retire", caption: "The ledger knocks the yield off your debt" },
] as const;

const STEP_MS = 2200;

export function FlowDiagram() {
  const reduced = usePrefersReducedMotion();
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (reduced) return;
    const id = setInterval(() => setTick((t) => t + 1), STEP_MS);
    return () => clearInterval(id);
  }, [reduced]);

  // Under reduced motion the diagram simply rests on its final, most
  // informative frame rather than cycling.
  const step = reduced ? 3 : tick % STEPS.length;
  const proving = step === 2;
  const retired = step === 3;

  return (
    <div className="w-full">
      {/* Screen-reader equivalent of the animation. */}
      <ol className="sr-only">
        {STEPS.map((s) => (
          <li key={s.key}>
            {s.label}: {s.caption}
          </li>
        ))}
      </ol>

      <div aria-hidden="true" className="card relative overflow-hidden p-4 sm:p-6">
        <div className="grid items-stretch gap-4 lg:grid-cols-[1fr_auto_1fr]">
          {/* ---------------------------------------------------- Ethereum */}
          <Panel
            side="yield"
            chain="Ethereum"
            network="Sepolia"
            role="Holds the money. States facts."
          >
            <Row label="Your deposit" value="$1,000.00" tone="ink" />
            <Meter tone="yield" fill={100} caption="Supplied to Aave V4 · Spoke" />
            <Row
              label="Yield accrued"
              value={step >= 1 ? "$12.40" : "$0.00"}
              tone="yield"
              pulsing={step === 1}
            />
            <Tag tone="yield" active={step >= 2}>
              TokensHarvested
            </Tag>
          </Panel>

          {/* ------------------------------------------------- Proof track */}
          <ProofTrack active={proving} />

          {/* -------------------------------------------------- Creditcoin */}
          <Panel
            side="credit"
            chain="Creditcoin"
            network="Testnet"
            role="Decides what they mean."
          >
            <Row
              label="Your debt"
              value={retired ? "$61.40" : "$73.80"}
              tone="credit"
              pulsing={retired}
            />
            <Meter tone="credit" fill={retired ? 61 : 74} caption="Debt against $1,000 collateral" />
            <Row
              label="Retired by yield"
              value={retired ? "$38.60" : "$26.20"}
              tone="ink"
            />
            <Tag tone="credit" active={retired}>
              DebtRetired
            </Tag>
          </Panel>
        </div>

        {/* ------------------------------------------------------ Step rail */}
        <ol className="mt-5 grid grid-cols-2 gap-2 border-t border-line pt-5 sm:grid-cols-4">
          {STEPS.map((s, i) => (
            <li key={s.key}>
              <div
                className={`flex items-center gap-2 transition-colors duration-300 ${
                  i === step ? "text-ink" : "text-faint"
                }`}
              >
                <span
                  className={`h-1.5 w-1.5 rounded-full transition-colors duration-300 ${
                    i === step
                      ? i < 2
                        ? "bg-yield-300"
                        : "bg-credit-400"
                      : "bg-line"
                  }`}
                />
                <span className="text-xs font-medium tracking-wide">{s.label}</span>
              </div>
              <p
                className={`mt-1 pl-3.5 text-[11px] leading-snug transition-opacity duration-300 ${
                  i === step ? "text-muted opacity-100" : "text-faint opacity-60"
                }`}
              >
                {s.caption}
              </p>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ pieces */

function Panel({
  side,
  chain,
  network,
  role,
  children,
}: {
  side: "yield" | "credit";
  chain: string;
  network: string;
  role: string;
  children: React.ReactNode;
}) {
  const accent = side === "yield" ? "bg-yield-300" : "bg-credit-400";
  const ring = side === "yield" ? "border-yield-300/20" : "border-credit-400/20";
  return (
    <div className={`rounded-xl border ${ring} bg-raised/60 p-4 sm:p-5`}>
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full ${accent}`} />
          <span className="font-display text-sm font-semibold">{chain}</span>
        </div>
        <span className="rounded-full border border-line px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-muted">
          {network}
        </span>
      </div>
      <p className="mt-1.5 text-[11px] leading-snug text-faint">{role}</p>
      <div className="mt-4 space-y-3.5">{children}</div>
    </div>
  );
}

function Row({
  label,
  value,
  tone,
  pulsing = false,
}: {
  label: string;
  value: string;
  tone: "ink" | "yield" | "credit";
  pulsing?: boolean;
}) {
  const color =
    tone === "yield" ? "text-yield-300" : tone === "credit" ? "text-credit-400" : "text-ink";
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-[11px] text-muted">{label}</span>
      <span
        className={`font-mono text-sm tabular ${color} transition-all duration-500 ${
          pulsing ? "scale-[1.04]" : "scale-100"
        }`}
      >
        {value}
      </span>
    </div>
  );
}

function Meter({
  tone,
  fill,
  caption,
}: {
  tone: "yield" | "credit";
  fill: number;
  caption: string;
}) {
  const bar = tone === "yield" ? "bg-yield-300" : "bg-credit-400";
  return (
    <div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-line">
        <div
          className={`h-full rounded-full ${bar} transition-[width] duration-700 ease-[cubic-bezier(0.16,1,0.3,1)]`}
          style={{ width: `${fill}%` }}
        />
      </div>
      <p className="mt-1.5 text-[10px] text-faint">{caption}</p>
    </div>
  );
}

function Tag({
  tone,
  active,
  children,
}: {
  tone: "yield" | "credit";
  active: boolean;
  children: React.ReactNode;
}) {
  const on =
    tone === "yield"
      ? "border-yield-300/40 text-yield-300"
      : "border-credit-400/40 text-credit-400";
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-md border px-2 py-1 font-mono text-[10px] transition-all duration-500 ${
        active ? on : "border-line text-faint"
      }`}
    >
      <span
        className={`h-1 w-1 rounded-full transition-colors duration-500 ${
          active ? "bg-current" : "bg-line"
        }`}
      />
      {children}
    </span>
  );
}

/**
 * The gap between the chains, and the packet that crosses it. Horizontal on
 * desktop, vertical on mobile — the same idea rotated.
 */
function ProofTrack({ active }: { active: boolean }) {
  return (
    <div className="relative flex items-center justify-center lg:w-32">
      {/* mobile: vertical */}
      <div className="relative h-16 w-px lg:hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-yield-300/40 via-line to-credit-400/40" />
        <span
          className={`absolute left-1/2 h-2 w-2 -translate-x-1/2 rounded-full bg-ink shadow-[0_0_12px_2px] shadow-yield-300/50 transition-all duration-[900ms] ease-[cubic-bezier(0.16,1,0.3,1)] ${
            active ? "top-[calc(100%-4px)] opacity-100" : "top-0 opacity-0"
          }`}
        />
      </div>

      {/* desktop: horizontal */}
      <div className="relative hidden h-px w-full lg:block">
        <div className="absolute inset-0 bg-gradient-to-r from-yield-300/40 via-line to-credit-400/40" />
        <span
          className={`absolute top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-ink shadow-[0_0_12px_2px] shadow-yield-300/50 transition-all duration-[900ms] ease-[cubic-bezier(0.16,1,0.3,1)] ${
            active ? "left-[calc(100%-8px)] opacity-100" : "left-0 opacity-0"
          }`}
        />
      </div>

      <div className="absolute -bottom-1 left-1/2 hidden -translate-x-1/2 text-center lg:block">
        <p
          className={`font-mono text-[10px] transition-colors duration-500 ${
            active ? "text-ink" : "text-faint"
          }`}
        >
          0x0FD2
        </p>
        <p className="mt-0.5 text-[9px] uppercase tracking-[0.14em] text-faint">
          proof only
        </p>
      </div>
    </div>
  );
}
