# Gap Analysis — Market Validation

## What It Does

`evm_copilot_gap_analysis` validates whether a project idea has whitespace in the EVM ecosystem. It runs 5 evidence channels in parallel:

1. Similar hackathon projects (top 20)
2. Launched protocols in the category (top 10 by TVL)
3. Dead/failed projects that attempted something similar
4. Research archive insights (EIPs, ethresear.ch, Vitalik blog)
5. VC investment theses (a16z, Paradigm, Dragonfly, etc.)

## Usage

```
evm_copilot_gap_analysis(
  idea="Cross-chain yield aggregator on Base",
  category="Yield Aggregator",
  targetChains=["base", "ethereum", "arbitrum"]
)
```

## Classification

- **full_gap** — Nothing exists. Genuine whitespace.
- **partial_gap** — Related work exists but differentiation is possible (different chain, segment, approach, or failed predecessors).
- **false_gap** — Crowded market. Multiple live competitors.

## Funding Signal

- **hot** — 3+ VCs actively investing or publishing theses in this category
- **warm** — 1-2 VCs with adjacent investments
- **cold** — No detected VC interest

## Lifecycle Intelligence

The response includes:
- **Graveyard check** — What dead projects tell us
- **Peak-to-trough** — TVL trajectory for the category
- **Hackathon-to-launch** — Conversion rate from hackathon to production

## When to Use

- User says "vet this idea", "should I build X", "is anyone building X"
- User asks for competitive analysis or market validation
- User wants to know if an idea is novel
- **Do NOT confuse with security auditing** — this is market gap analysis

## After Gap Analysis

Present:
1. The verdict (full/partial/false gap + funding signal)
2. Key evidence (live competitors, dead predecessors, VC interest)
3. Differentiation angles if partial gap
4. Recommendations
