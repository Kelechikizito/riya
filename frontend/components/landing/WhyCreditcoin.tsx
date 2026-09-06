import { Section } from "@/components/ui/Section";

const PILLARS = [
  {
    title: "Verified by the chain, not a committee",
    body: "Creditcoin re-checks the Ethereum block itself through the Block Prover Precompile. riya's ASC additionally requires receiptStatus == 1 and pins each event to the contract that may emit it — so a proof that decodes but did not succeed is rejected.",
    mono: "0x0FD2",
    icon: "shield",
    side: "credit",
  },
  {
    title: "One copy of the accounting",
    body: "Ethereum holds the money and states facts. Creditcoin decides what they mean — collateral, fee, score, limit, debt. State that exists in one place cannot drift from a copy, so an entire class of desync bugs never gets written.",
    mono: "no mirror state",
    icon: "layers",
    side: "yield",
  },
  {
    title: "The destination is the point",
    body: "rUSD is an ordinary ERC-20 on Creditcoin. Any Creditcoin wallet, contract or DEX can accept it. Your position never needs to leave, and that is a feature rather than a truncation.",
    mono: "rUSD · 6 decimals",
    icon: "coin",
    side: "credit",
  },
  {
    title: "Nothing waits on writability",
    body: "Every proof travels inbound: Ethereum to Creditcoin. riya needs no outbound message, so nothing in the product is blocked on a capability that is still in audit. What ships today is complete on its own terms.",
    mono: "readability only",
    icon: "arrow",
    side: "yield",
  },
] as const;

function Icon({ name, className }: { name: string; className: string }) {
  const common = {
    className,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.5,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  switch (name) {
    case "shield":
      return (
        <svg {...common}>
          <path d="M12 3l7 3v5.5c0 4.2-2.9 7.9-7 9.5-4.1-1.6-7-5.3-7-9.5V6l7-3z" />
          <path d="M9 12l2 2 4-4" />
        </svg>
      );
    case "layers":
      return (
        <svg {...common}>
          <path d="M12 3l8 4.5-8 4.5-8-4.5L12 3z" />
          <path d="M4 12.5L12 17l8-4.5" />
          <path d="M4 16.5L12 21l8-4.5" />
        </svg>
      );
    case "coin":
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="8.5" />
          <path d="M12 7.5v9M14.5 9.5h-3.2a1.8 1.8 0 000 3.6h1.4a1.8 1.8 0 010 3.6H9.5" />
        </svg>
      );
    default:
      return (
        <svg {...common}>
          <path d="M4 12h15" />
          <path d="M14 7l5 5-5 5" />
          <path d="M4 6v12" />
        </svg>
      );
  }
}

export function WhyCreditcoin() {
  return (
    <Section
      id="why"
      eyebrow="Technical alignment"
      title="Why this can only be built on Creditcoin"
      lede="The useful test for a cross-chain design is whether it would still work, unchanged, on any other L2. riya answers no — four times."
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {PILLARS.map((p) => {
          const isYield = p.side === "yield";
          return (
            <article
              key={p.title}
              className="card group p-6 transition-colors duration-300 hover:border-muted/40 sm:p-7"
            >
              <div
                className={`inline-flex h-10 w-10 items-center justify-center rounded-lg border ${
                  isYield
                    ? "border-yield-300/25 text-yield-300"
                    : "border-credit-400/25 text-credit-400"
                }`}
              >
                <Icon name={p.icon} className="h-5 w-5" />
              </div>
              <h3 className="mt-5 text-lg font-semibold">{p.title}</h3>
              <p className="mt-3 text-[15px] leading-relaxed text-muted">
                {p.body}
              </p>
              <p
                className={`mt-5 font-mono text-xs ${
                  isYield ? "text-yield-300/70" : "text-credit-400/70"
                }`}
              >
                {p.mono}
              </p>
            </article>
          );
        })}
      </div>

      <div className="card mt-4 border-dashed p-6 sm:p-7">
        <p className="text-[15px] leading-relaxed text-muted">
          <span className="text-ink">The honest version:</span> a generic yield
          vault could ship on any chain tomorrow. riya could not. Take the
          precompile away and there is no way for the loan to learn that the
          collateral earned anything — the product stops existing rather than
          getting slower.
        </p>
      </div>
    </Section>
  );
}
