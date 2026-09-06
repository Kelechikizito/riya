"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ConnectButton } from "@/components/site/ConnectButton";
import { Logo } from "@/components/brand/Logo";

const LINKS = [
  { href: "/#how", label: "How it works" },
  { href: "/#credit", label: "Credit" },
  { href: "/#start", label: "Get started" },
  { href: "/#roadmap", label: "Roadmap" },
  { href: "/docs", label: "Docs" },
];

export function SiteNav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={`sticky top-0 z-50 transition-colors duration-300 ${
        scrolled
          ? "border-b border-line bg-void/95 backdrop-blur-xl"
          : "border-b border-transparent"
      }`}
    >
      <nav
        aria-label="Main"
        className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-6 px-5 sm:px-8"
      >
        <Link href="/" className="shrink-0 cursor-pointer">
          <Logo />
        </Link>

        <ul className="hidden items-center gap-7 lg:flex">
          {LINKS.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                className="cursor-pointer text-sm text-muted transition-colors duration-200 hover:text-ink"
              >
                {link.label}
              </Link>
            </li>
          ))}
        </ul>

        <div className="flex items-center gap-2.5">
          <div className="hidden sm:block">
            <ConnectButton />
          </div>
          <Link
            href="/app"
            className="hidden cursor-pointer rounded-full bg-yield-300 px-4 py-2 text-sm font-medium text-void transition-colors duration-200 hover:bg-yield-200 sm:inline-flex"
          >
            Open app
          </Link>

          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? "Close menu" : "Open menu"}
            className="grid h-11 w-11 cursor-pointer place-items-center rounded-lg border border-line text-ink lg:hidden"
          >
            <svg
              viewBox="0 0 20 20"
              className="h-5 w-5"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              aria-hidden="true"
            >
              {open ? (
                <path d="M5 5l10 10M15 5L5 15" />
              ) : (
                <path d="M3 6h14M3 10h14M3 14h14" />
              )}
            </svg>
          </button>
        </div>
      </nav>

      {open && (
        <div
          id="mobile-nav"
          className="border-t border-line bg-void/95 backdrop-blur-xl lg:hidden"
        >
          <ul className="mx-auto flex max-w-6xl flex-col px-5 py-2 sm:px-8">
            {LINKS.map((link) => (
              <li key={link.href}>
                <Link
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className="block cursor-pointer py-3 text-[15px] text-muted transition-colors hover:text-ink"
                >
                  {link.label}
                </Link>
              </li>
            ))}
            <li className="flex flex-col gap-3 py-4 sm:hidden">
              <ConnectButton compact />
              <Link
                href="/app"
                onClick={() => setOpen(false)}
                className="cursor-pointer rounded-full bg-yield-300 px-4 py-2.5 text-center text-sm font-medium text-void"
              >
                Open app
              </Link>
            </li>
          </ul>
        </div>
      )}
    </header>
  );
}
