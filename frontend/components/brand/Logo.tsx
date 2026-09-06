/**
 * The riya mark: two arcs facing each other with a gap between them.
 *
 * The left arc is teal (Ethereum, where the money sits), the right is amber
 * (Creditcoin, where the debt sits), and they never touch. The gap is the
 * proof that crosses it — which is the entire product in one glyph.
 */
export function Mark({ className = "h-7 w-7" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      fill="none"
      className={className}
      aria-hidden="true"
      focusable="false"
    >
      {/* Ethereum side — opens right, toward the gap */}
      <path
        d="M13 4.5A12.4 12.4 0 0 0 13 27.5"
        stroke="var(--color-yield-300)"
        strokeWidth="3.2"
        strokeLinecap="round"
      />
      {/* Creditcoin side — opens left, mirrored */}
      <path
        d="M19 4.5a12.4 12.4 0 0 1 0 23"
        stroke="var(--color-credit-400)"
        strokeWidth="3.2"
        strokeLinecap="round"
      />
      {/* The proof in the gap */}
      <circle cx="16" cy="16" r="2.1" fill="var(--color-ink)" />
    </svg>
  );
}

export function Wordmark({ className = "" }: { className?: string }) {
  return (
    <span
      className={`font-display text-[1.35rem] font-semibold tracking-[-0.03em] lowercase leading-none ${className}`}
    >
      riya
    </span>
  );
}

export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <Mark />
      <Wordmark />
      <span className="sr-only">riya home</span>
    </span>
  );
}
