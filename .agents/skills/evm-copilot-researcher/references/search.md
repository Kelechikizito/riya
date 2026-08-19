# Searching Projects

## Basic Search

Use `evm_copilot_search_projects` for semantic + keyword search across 18,000+ projects.

```
evm_copilot_search_projects(query="cross-chain lending", limit=10)
```

## Filtering by Lifecycle

The most powerful feature is lifecycle filtering:

- `lifecycle: ["launched"]` — live protocols with TVL
- `lifecycle: ["hackathon"]` — ETHGlobal/Devpost submissions
- `lifecycle: ["dead", "rugged"]` — failed projects with death reasons
- No filter — all lifecycle stages combined

## Filtering by Chain

```
evm_copilot_search_projects(query="DEX", chains=["arbitrum", "base"])
```

Supported chains: ethereum, polygon, arbitrum, optimism, base, avalanche, bsc, zksync, linea, scroll, blast, mantle, mode

## Filtering by Category

```
evm_copilot_search_projects(query="yield", category=["Yield Aggregator"])
```

Categories come from DeFiLlama: Dexs, Lending, Bridge, Yield, Yield Aggregator, Derivatives, Farm, CDP, RWA, Liquid Staking, Options, etc.

Note: DeFiLlama uses "Dexs" (with an 's'), not "DEX".

## Full Picture Search

For comprehensive research, run multiple searches:

1. `evm_copilot_search_projects(query="X", lifecycle=["launched"])` — who's live
2. `evm_copilot_search_projects(query="X", lifecycle=["dead", "rugged"])` — who died
3. `evm_copilot_search_projects(query="X", lifecycle=["hackathon"])` — who's tried building it

## Getting Project Details

After finding a project, use its ID for full details:

```
evm_copilot_get_project(id="uuid-here")
```

Returns: TVL, team, chains, audit status, death reason, links, tags.
