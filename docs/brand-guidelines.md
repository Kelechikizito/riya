# riya — Brand Guidelines v1.0

> Last updated: 2026-09-06
> Status: Draft — hackathon submission identity

## Quick Reference

| Element | Value |
|---------|-------|
| Primary Color | #5EEAD4 |
| Secondary Color | #FBBF24 |
| Primary Font | Space Grotesk |
| Voice | Plain, unhurried, structurally honest |

The whole identity rests on one idea: **riya is two chains doing two different
jobs.** Ethereum holds the money and states facts. Creditcoin decides what they
mean. The brand encodes that split in colour, so the page teaches the mechanism
before anyone reads a word.

---

## 1. Color Palette

Riya is a **duotone** system, and the two hues are semantic, not decorative.
Never use teal for a debt figure or amber for a yield figure — the colour is
load-bearing information.

### Ethereum / Yield side — teal

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Yield Teal | #5EEAD4 | rgb(94,234,212) | Primary CTA, deposits, collateral, source-chain surfaces |
| Yield Deep | #2DD4BF | rgb(45,212,191) | Hover and pressed states |
| Harvest Green | #34D399 | rgb(52,211,153) | Realised yield, harvest events, positive deltas |

### Creditcoin / Credit side — amber

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Credit Amber | #FBBF24 | rgb(251,191,36) | Debt figures, credit score, destination-chain surfaces |
| Limit Amber | #F59E0B | rgb(245,158,11) | Borrow limit, LTV ladder, hover on amber controls |
| Ember | #D97706 | rgb(217,119,6) | Deep amber for gradient tails only, never for text |

### Neutral Palette

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Void | #05090B | rgb(5,9,11) | Page background |
| Surface | #0C1416 | rgb(12,20,22) | Cards, raised panels |
| Surface Raised | #131F22 | rgb(19,31,34) | Nested panels, table rows, inputs |
| Border | #1E2E31 | rgb(30,46,49) | Hairlines, card edges |
| Text | #E7F0EE | rgb(231,240,238) | Headings and body |
| Text Muted | #8B9E9B | rgb(139,158,155) | Captions, labels, secondary copy |
| Text Faint | #788C89 | rgb(120,140,137) | Metadata, timestamps, de-emphasised detail |

### Semantic Colors

| State | Hex | Usage |
|-------|-----|-------|
| Success | #34D399 | Proof verified, harvest applied |
| Warning | #FBBF24 | Pending proof, unverified state |
| Error | #F87171 | Reverts, failed proofs, risk callouts |
| Info | #5EEAD4 | Neutral informational messages |

### Accessibility

- Text (#E7F0EE) on Void (#05090B): 16.1:1 — AAA.
- Text Muted (#8B9E9B) on Void: 7.1:1 — AAA.
- Text Faint (#788C89) on Void: 5.6:1, and 4.7:1 on the raised surface — AA at
  every size it is used, which matters because it carries real captions rather
  than decoration.
- Yield Teal (#5EEAD4) on Void: 13.4:1 — AAA.
- Credit Amber (#FBBF24) on Void: 11.7:1 — AAA.
- Both accents are used as **dark text on light fills** for buttons
  (#05090B on #5EEAD4 = 13.4:1), never light-on-light.
- Colour is never the only channel: every teal/amber distinction is
  reinforced by a label, an icon, or position in the layout.

---

## 2. Typography

### Font Stack

```css
--font-heading: 'Space Grotesk', system-ui, -apple-system, sans-serif;
--font-body: 'Inter', system-ui, -apple-system, sans-serif;
--font-mono: 'JetBrains Mono', 'Fira Code', monospace;
```

Space Grotesk carries the headlines: geometric, slightly odd, high x-height, and
tagged in the design data specifically for DeFi and trustless-systems brands.
Inter does the reading. JetBrains Mono is reserved for things that are literally
machine-truth — addresses, hashes, event names, contract identifiers, and every
figure denominated in dollars. Money is always mono in riya.

### Type Scale

| Element | Size (Desktop) | Size (Mobile) | Weight | Line Height |
|---------|----------------|---------------|--------|-------------|
| Display | 76px | 40px | 600 | 1.02 |
| H1 | 52px | 32px | 600 | 1.08 |
| H2 | 38px | 28px | 600 | 1.15 |
| H3 | 24px | 20px | 600 | 1.3 |
| Body Large | 19px | 17px | 400 | 1.6 |
| Body | 16px | 16px | 400 | 1.6 |
| Small | 14px | 14px | 400 | 1.5 |
| Caption | 12px | 12px | 500 | 1.4 |
| Eyebrow | 12px | 12px | 500 | 1.2 (0.14em tracking, uppercase) |

Display and H1 use `-0.03em` tracking. Eyebrows are uppercase, tracked wide, and
always Text Muted.

---

## 3. Logo

The mark is two arcs facing each other with a gap between them — the two chains,
and the proof that crosses. The left arc is teal, the right is amber, and they
never touch. The gap is the point.

- Minimum size: 20px tall for the mark, 72px wide for the lockup.
- Clear space: one arc-width on all sides.
- The wordmark is **always lowercase** — `riya`, never `Riya` or `RIYA` — set in
  Space Grotesk 600 with -0.03em tracking.
- On light or photographic backgrounds, use the single-colour Void version.
- Never recolour the arcs to a single hue, never add a stroke, never rotate.

---

## 4. Voice

**Plain, unhurried, structurally honest.**

riya's product claim sounds like a scam if you oversell it — "your loan repays
itself" is one register away from a yield-farm rug. The entire voice strategy is
therefore to *undersell*, and to let the mechanism carry the excitement.

| Do | Don't |
|----|-------|
| "You never make a repayment. You just wait." | "Earn passive income effortlessly!" |
| "Your collateral is locked in v1. Here's why." | Quietly omit the lock |
| "If Aave is impaired, collateral shrinks and the debt doesn't." | Hide the risk in a footnote |
| Name the primitive: "Block Prover Precompile at 0x0FD2" | "Powered by advanced cross-chain technology" |
| Short sentences. One idea each. | Stacked clauses and hedging |

**Never** use: revolutionary, seamless, effortless, game-changing, unlock (as a
verb for value), 🚀, APY promises, or any number presented as a guarantee.

**Always** state limits in the same breath as capabilities. A judge who finds a
risk you hid discounts everything else on the page; a risk you surfaced first
reads as competence.

### Sentence-level rules

- Second person. "You deposit", not "users deposit".
- Present tense for how it works, future tense only in the roadmap.
- Dollar amounts as concrete worked examples ($1,000 → $100 → $0), never ranges.
- Never claim writability. It is not released; the roadmap may want it, the
  product may not depend on it.

---

## 5. Messaging Framework

**One-liner:** Deposit on Ethereum. Borrow on Creditcoin. The loan repays itself.

**Positioning:** riya is Alchemix's self-repaying loan, split across two chains —
with the savings on Ethereum and the debt on Creditcoin, joined by a proof rather
than a bridge.

**Proof points, in the order they should be argued:**

1. The model is proven. Alchemix already showed self-repaying loans work.
2. The split is native. Creditcoin verifies the Ethereum yield itself, via the
   Block Prover Precompile — no multisig, no relayer trust, no wrapped bridge.
3. The destination is the point. RiyaUSD is an ERC-20 that any Creditcoin
   contract, wallet or DEX can accept. Never leaving Creditcoin is a feature.
4. Credit is earned, not bought. The score only moves when *yield* retires debt,
   never when cash does — so the ladder measures productive collateral.
5. Nobody gets liquidated. There is no liquidation path in the protocol at all.

**Audience:** people who already hold stablecoins on Ethereum and want spendable
liquidity without selling, plus Creditcoin-native users who want a dollar asset
with real off-chain backing.

---

## 6. Consistency Rules

- Money is mono. Every dollar figure uses JetBrains Mono with tabular numerals.
- Teal is Ethereum. Amber is Creditcoin. No exceptions anywhere in the product.
- Every claim about a contract links to the contract or the walkthrough doc.
- Icons are SVG (Lucide/Heroicons geometry). Emoji are never icons.
- Motion is 200–300ms, `cubic-bezier(0.16,1,0.3,1)`, and every non-essential
  animation is skipped under `prefers-reduced-motion`.
