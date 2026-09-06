import Link from "next/link";
import { Logo } from "@/components/brand/Logo";
import { BLOCK_PROVER_PRECOMPILE } from "@/lib/chains";

const COLUMNS = [
  {
    title: "Product",
    links: [
      { href: "/#how", label: "How it works" },
      { href: "/#credit", label: "Credit score" },
      { href: "/#start", label: "Get started" },
      { href: "/app", label: "Dashboard" },
    ],
  },
  {
    title: "Project",
    links: [
      { href: "/#roadmap", label: "Roadmap" },
      { href: "/#risk", label: "Risks" },
      { href: "/docs", label: "Documentation" },
    ],
  },
  {
    title: "Ecosystem",
    links: [
      { href: "https://creditcoin.org", label: "Creditcoin", external: true },
      { href: "https://docs.creditcoin.org", label: "Attestcoin docs", external: true },
      { href: "https://aave.com", label: "Aave", external: true },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8">
        <div className="grid gap-12 md:grid-cols-[1.4fr_1fr_1fr_1fr]">
          <div>
            <Logo />
            <p className="mt-4 max-w-xs text-sm leading-relaxed text-muted">
              Deposit on Ethereum. Borrow on Creditcoin. The loan repays itself.
            </p>
            <p className="mt-5 font-mono text-xs leading-relaxed text-faint">
              Block Prover Precompile
              <br />
              <span className="text-muted">{BLOCK_PROVER_PRECOMPILE}</span>
            </p>
          </div>

          {COLUMNS.map((col) => (
            <div key={col.title}>
              <h3 className="font-sans text-xs font-semibold uppercase tracking-[0.14em] text-ink">
                {col.title}
              </h3>
              <ul className="mt-4 space-y-3">
                {col.links.map((link) => (
                  <li key={link.href}>
                    {"external" in link && link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noreferrer"
                        className="cursor-pointer text-sm text-muted transition-colors hover:text-ink"
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link
                        href={link.href}
                        className="cursor-pointer text-sm text-muted transition-colors hover:text-ink"
                      >
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-14 flex flex-col gap-3 border-t border-line pt-8 text-xs text-faint sm:flex-row sm:items-center sm:justify-between">
          <p>
            riya — built for the Creditcoin hackathon. Testnet software,
            unaudited. Not financial advice.
          </p>
          <p className="font-mono">
            Ethereum Sepolia → Creditcoin Testnet
          </p>
        </div>
      </div>
    </footer>
  );
}
