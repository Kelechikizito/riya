import { SiteNav } from "@/components/site/SiteNav";
import { SiteFooter } from "@/components/site/SiteFooter";
import { Hero } from "@/components/landing/Hero";
import { HowItWorks } from "@/components/landing/HowItWorks";
import { WhyCreditcoin } from "@/components/landing/WhyCreditcoin";
import { CreditLadder } from "@/components/landing/CreditLadder";
import { Onboarding } from "@/components/landing/Onboarding";
import { Roadmap } from "@/components/landing/Roadmap";
import { Risks } from "@/components/landing/Risks";
import { DocsCta } from "@/components/landing/DocsCta";

export default function Home() {
  return (
    <>
      <SiteNav />
      <main className="flex-1">
        <Hero />
        <HowItWorks />
        <WhyCreditcoin />
        <CreditLadder />
        <Onboarding />
        <Roadmap />
        <Risks />
        <DocsCta />
      </main>
      <SiteFooter />
    </>
  );
}
