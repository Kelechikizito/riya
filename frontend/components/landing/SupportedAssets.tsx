"use client";

import Link from "next/link";
import { Section } from "@/components/ui/Section";
import { AAVE_V4, SOURCE_CHAIN } from "@/lib/chains";
import { ADDRESSES, ASSUMED_YIELD_RATE_BPS } from "@/lib/contracts";
import { formatPercent, formatUsd } from "@/lib/format";
import { useVault } from "@/lib/useVault";

type Asset = {
  symbol: string;
  name: string;
  /** Live means there is a deployed adapter and escrow for it. Nothing else does. */
  live: boolean;
  /** Why it is not live yet. Shown instead of a rate. */
  blocker?: string;
};

/**
 * One adapter serves exactly one asset: `AaveV4Adapter.I_ASSET` and `I_RESERVE_ID` are
 * immutable, `RiyaEscrow` pins one adapter, and `RiyaASC` pins one escrow. So a second asset
 * is not a deployment, it is a second adapter, a second escrow, an ASC that accepts several
 * emitters, and a ledger that prices collateral per asset. Said plainly rather than shown as
 * a greyed-out button that implies it nearly works.
 */
const ASSETS: readonly Asset[] = [
  { symbol: "USDC", name: "USD Coin", live: true },
  {
    symbol: "USDT",
    name: "Tether USD",
    live: false,
    blocker: "Needs its own adapter and escrow",
  },
  {
    symbol: "DAI",
    name: "Dai Stablecoin",
    live: false,
    blocker: "Needs its own adapter and escrow",
  },
  {
    symbol: "wETH",
    name: "Wrapped Ether",
    live: false,
    blocker: "Needs an oracle. The ledger counts collateral in dollars",
  },
];

export function SupportedAssets() {
  const { vault, live } = useVault();

  return (
    <Section
      id="assets"
      eyebrow="Collateral"
      title="What you can deposit"
      lede="One asset today, and an honest reason for each of the others. Your dollars never leave Ethereum: they sit in Aave earning, and only a proof crosses to Creditcoin."
    >
      <div className="grid gap-4 lg:grid-cols-[1.4fr_1fr]">
        {/* -------------------------------------------------------- the table */}
        <div className="card overflow-hidden">
          <div className="grid grid-cols-[1fr_auto_auto] gap-4 border-b border-line px-6 py-3 text-[11px] uppercase tracking-[0.14em] text-faint">
            <span>Asset</span>
            <span className="text-right">Yield source</span>
            <span className="text-right">Status</span>
          </div>

          {ASSETS.map((asset) => (
            <div
              key={asset.symbol}
              className="grid grid-cols-[1fr_auto_auto] items-center gap-4 border-b border-line px-6 py-4 last:border-b-0"
            >
              <div className="min-w-0">
                <p className={asset.live ? "text-[15px] text-ink" : "text-[15px] text-faint"}>
                  {asset.symbol}
                </p>
                <p className="mt-0.5 truncate text-[13px] text-faint">
                  {asset.blocker ?? asset.name}
                </p>
              </div>

              <span className="text-right font-mono text-[13px] text-faint">
                {asset.live ? "Aave V4" : "—"}
              </span>

              <div className="text-right">
                {asset.live ? (
                  <Link
                    href="/app"
                    className="inline-block cursor-pointer rounded-full bg-yield-300 px-4 py-1.5 text-[13px] font-medium text-void transition-colors duration-200 hover:bg-yield-200"
                  >
                    Deposit
                  </Link>
                ) : (
                  <span className="inline-block cursor-not-allowed rounded-full border border-line px-4 py-1.5 text-[13px] text-faint">
                    Roadmap
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>

        {/* ------------------------------------------------------ the numbers */}
        <div className="flex flex-col gap-4">
          <div className="card p-6">
            <div className="flex items-center justify-between">
              <p className="eyebrow">Riya&rsquo;s position on Ethereum</p>
              {!live && (
                <span className="text-[10px] uppercase tracking-[0.14em] text-faint">
                  Offline
                </span>
              )}
            </div>

            <dl className="mt-5 space-y-3">
              <Row label="Supplied to Aave" value={formatUsd(vault.principal)} />
              <Row label="Held by Aave now" value={formatUsd(vault.totalAssets)} />
              <Row
                label="Yield not yet harvested"
                value={formatUsd(vault.yieldAccrued)}
                tone="yield"
              />
              <Row label="Harvest threshold" value={formatUsd(vault.minHarvest)} />
            </dl>

            <p className="mt-5 text-[13px] leading-relaxed text-faint">
              Everything above what was supplied is yield, and{" "}
              <span className="text-muted">harvest()</span> may move exactly that and nothing
              else. Read live from{" "}
              <a
                href={`${SOURCE_CHAIN.explorer}/address/${ADDRESSES.adapter ?? ""}`}
                target="_blank"
                rel="noreferrer"
                className="text-muted underline decoration-line decoration-dotted underline-offset-4 hover:text-yield-300"
              >
                the adapter
              </a>
              .
            </p>
          </div>

          <div className="card p-6">
            <p className="eyebrow">On the rate</p>
            <p className="mt-3 text-[14px] leading-relaxed text-muted">
              riya does not read an APY on chain, and does not claim one. The ledger takes the
              rate as an argument to{" "}
              <span className="font-mono text-[13px] text-ink">selfRepayRateBps</span>, so the
              assumption is the caller&rsquo;s and this page owns it. Today it assumes{" "}
              <span className="text-yield-300">
                {formatPercent(ASSUMED_YIELD_RATE_BPS, 1)}
              </span>
              .
            </p>
            <p className="mt-3 text-[13px] leading-relaxed text-faint">
              Aave V4 is deployed on Ethereum Mainnet and nowhere else, so the demo runs
              against a stand-in on {SOURCE_CHAIN.name}. The production venue is{" "}
              <a
                href={`${AAVE_V4.explorer}/address/${AAVE_V4.spoke}`}
                target="_blank"
                rel="noreferrer"
                className="text-muted underline decoration-line decoration-dotted underline-offset-4 hover:text-yield-300"
              >
                the Aave V4 Spoke
              </a>
              , reserve {AAVE_V4.usdcReserveId}. Check the real rate there.
            </p>
          </div>
        </div>
      </div>
    </Section>
  );
}

function Row({
  label,
  value,
  tone = "ink",
}: {
  label: string;
  value: string;
  tone?: "ink" | "yield";
}) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="text-[14px] text-muted">{label}</dt>
      <dd
        className={`font-mono text-[15px] tabular ${
          tone === "yield" ? "text-yield-300" : "text-ink"
        }`}
      >
        {value}
      </dd>
    </div>
  );
}
