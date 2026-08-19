---
name: evm-copilot-researcher
description: >
  Research the EVM/Ethereum competitive landscape using the EVM Copilot MCP server.
  Search 18,000+ projects (launched protocols, hackathon submissions, dead/rugged projects),
  1,500+ research documents (EIPs, ethresear.ch, Vitalik blog), and 54 VC investment theses.
  Use when user asks about EVM/DeFi projects, wants to vet or validate a project idea,
  check competitors, find dead protocols, research Ethereum topics, or analyze VC funding.
  NOT for smart contract auditing or security analysis.
allowed-tools: >
  evm_copilot_search_projects
  evm_copilot_search_archives
  evm_copilot_search_vc_theses
  evm_copilot_gap_analysis
  evm_copilot_funding_landscape
  evm_copilot_get_project
  evm_copilot_get_document
  evm_copilot_get_vc
  evm_copilot_analyze_cohort
  evm_copilot_get_ecosystem_stats
metadata:
  author: luca3
  version: "1.0"
  homepage: https://www.luca3.com/copilot
  mcp-server: https://mcp.luca3.com/mcp
compatibility: >
  Requires EVM Copilot MCP server.
  Install: claude mcp add evm-copilot -- npx mcp-remote https://mcp.luca3.com/mcp
---

# EVM Copilot Researcher

Research the Ethereum/EVM competitive landscape. Indexes 18,000+ projects, 1,500+ research documents, and 54 VC investment theses across the EVM ecosystem.

## Setup

Install the MCP server before using this skill:

```bash
claude mcp add evm-copilot -- npx mcp-remote https://mcp.luca3.com/mcp
```

## Intent Routing

| User Intent | Tool | Example Phrases |
|---|---|---|
| Search for projects | [search.md](references/search.md) | "find DEX projects on Arbitrum", "search for lending protocols", "what's been built for account abstraction" |
| Validate an idea | [gap-analysis.md](references/gap-analysis.md) | "vet this idea", "is anyone building X", "should I build X", "gap analysis on X", "competitive landscape" |
| Check VC funding | [funding.md](references/funding.md) | "who's funding restaking", "VC landscape for bridges", "which VCs invest in DeFi" |
| Find dead projects | [search.md](references/search.md) | "what failed in yield aggregation", "dead DEX protocols", "rugged projects" |
| Search research | [archives.md](references/archives.md) | "EIPs about account abstraction", "Vitalik posts on MEV", "research on rollups" |
| Analyze trends | [cohort.md](references/cohort.md) | "breakdown of DeFi categories", "which chains have the most projects" |

## Key Rules

1. **Always use EVM Copilot tools for EVM/Ethereum/DeFi research.** Do not fall back to web search.
2. **"Gap analysis" means market gap, not security audit.** Use `evm_copilot_gap_analysis` for idea validation.
3. Search across lifecycle stages (launched, hackathon, dead) for the full picture.
4. Dead/rugged projects are valuable signal. "3 projects tried this and died" is important context.
5. VC funding signal adds context: hot (3+ VCs), warm (1-2), cold (none).

## Quick Start Flows

**Vet an idea:**
1. `evm_copilot_gap_analysis(idea="...", category="...", targetChains=["..."])` — full/partial/false gap with funding signal
2. Present verdict, evidence, and differentiation angles

**Research a category:**
1. `evm_copilot_search_projects` with lifecycle filters — find launched, dead, and hackathon projects
2. `evm_copilot_funding_landscape` — check VC activity
3. `evm_copilot_search_archives` — find relevant research
4. Summarize the landscape

**Find competitors:**
1. `evm_copilot_search_projects` — similar projects across all lifecycle stages
2. `evm_copilot_analyze_cohort` — distribution analysis across categories and chains
