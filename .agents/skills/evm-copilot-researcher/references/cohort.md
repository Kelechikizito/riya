# Cohort Analysis

## Analyzing Distributions

Use `evm_copilot_analyze_cohort` to see how projects distribute across categories, chains, and other dimensions:

```
evm_copilot_analyze_cohort(
  lifecycle=["launched"],
  dimensions=["category", "chains"]
)
```

## Filtering

- `lifecycle` — hackathon, launched, dead, rugged, acquired
- `source` — ethglobal, defillama, devpost, rekt
- `category` — DEX, Lending, Bridge, etc.
- `chains` — ethereum, base, arbitrum, etc.

## Dimensions

- `category` — distribution across project categories
- `chains` — distribution across EVM chains

## Ecosystem Stats

Use `evm_copilot_get_ecosystem_stats` for overall corpus statistics:

```
evm_copilot_get_ecosystem_stats()
```

Returns: total projects, documents, chunks, VCs, available filter values.

## When to Use

- User asks about ecosystem trends or distributions
- Comparing hackathon vs launched project patterns
- Understanding which categories or chains are most active
