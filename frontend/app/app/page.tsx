import type { Metadata } from "next";
import { SiteNav } from "@/components/site/SiteNav";
import { SiteFooter } from "@/components/site/SiteFooter";
import { Dashboard } from "@/components/app/Dashboard";

export const metadata: Metadata = {
  title: "Dashboard",
  description:
    "Your riya position: collateral on Ethereum, debt on Creditcoin, and how much of it your yield has already retired.",
};

export default function AppPage() {
  return (
    <>
      <SiteNav />
      <main className="flex-1">
        <Dashboard />
      </main>
      <SiteFooter />
    </>
  );
}
