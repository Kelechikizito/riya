/** USDC and rUSD both use 6 decimals. Every figure in riya is 6dp. */
export const ASSET_DECIMALS = 6;

const dollars = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 2,
});

const dollarsWhole = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

/** 6dp bigint → "$1,234.56". Pass `whole` for headline figures. */
export function formatUsd(value: bigint, whole = false): string {
  const n = Number(value) / 10 ** ASSET_DECIMALS;
  return (whole ? dollarsWhole : dollars).format(n);
}

export function formatPercent(bps: number | bigint, digits = 0): string {
  return `${(Number(bps) / 100).toFixed(digits)}%`;
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/**
 * The headline number on the dashboard: how long until the debt reaches zero
 * with the user contributing nothing.
 *
 * The ledger's `selfRepayRateBps` returns the share of current debt retired per
 * year at a given yield rate, so years-to-zero is just its reciprocal. Returns
 * null when there is no debt, or when the rate is too small to be meaningful.
 */
export function yearsToZero(selfRepayRateBps: bigint): number | null {
  if (selfRepayRateBps <= 0n) return null;
  return 10_000 / Number(selfRepayRateBps);
}

export function formatDuration(years: number): string {
  if (years < 1) {
    const months = Math.max(1, Math.round(years * 12));
    return `${months} month${months === 1 ? "" : "s"}`;
  }
  return `${years.toFixed(1)} years`;
}
