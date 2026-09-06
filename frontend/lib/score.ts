/**
 * The credit ladder from `LoanLedger.maxLtvBps`.
 *
 * The score measures how much debt *yield* has retired, against a target of 20%
 * of collateral. `repay()` deliberately does not touch it — otherwise borrowing
 * $100 and repaying $100 in cash on repeat would buy the top tier without ever
 * letting the collateral work.
 */
export const SCORE_TIERS = [
  { min: 0, max: 19, ltvBps: 1_000, label: "Opening" },
  { min: 20, max: 39, ltvBps: 2_000, label: "Establishing" },
  { min: 40, max: 59, ltvBps: 3_000, label: "Proven" },
  { min: 60, max: 84, ltvBps: 4_000, label: "Trusted" },
  { min: 85, max: 100, ltvBps: 5_000, label: "Full" },
] as const;

export type ScoreTier = (typeof SCORE_TIERS)[number];

export function tierForScore(score: number): ScoreTier {
  return (
    SCORE_TIERS.find((t) => score >= t.min && score <= t.max) ?? SCORE_TIERS[0]
  );
}
