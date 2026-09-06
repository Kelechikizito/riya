import type { Metadata } from "next";
import { Inter, JetBrains_Mono, Space_Grotesk } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
});

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://riya.finance"),
  title: {
    default: "riya — the loan that repays itself",
    template: "%s · riya",
  },
  description:
    "Deposit USDC on Ethereum. Borrow on Creditcoin. The yield your deposit earns is proven across and quietly retires the debt — no repayments, no liquidations.",
  keywords: [
    "Creditcoin",
    "self-repaying loan",
    "Attestcoin",
    "Block Prover Precompile",
    "Aave",
    "cross-chain proof",
    "DeFi",
  ],
  openGraph: {
    title: "riya — the loan that repays itself",
    description:
      "Deposit on Ethereum. Borrow on Creditcoin. The loan repays itself.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "riya — the loan that repays itself",
    description:
      "Deposit on Ethereum. Borrow on Creditcoin. The loan repays itself.",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${spaceGrotesk.variable} ${inter.variable} ${jetbrainsMono.variable} h-full antialiased`}
    >
      <body className="min-h-full bg-void text-ink flex flex-col">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
