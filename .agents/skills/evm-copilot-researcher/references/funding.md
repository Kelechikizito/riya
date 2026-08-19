# VC Funding Intelligence

## Funding Landscape

Use `evm_copilot_funding_landscape` to see which VCs are active in a category:

```
evm_copilot_funding_landscape(category="Lending")
```

Returns:
- Active VCs with portfolio companies in the category
- Relevant investment theses
- Category stats (live protocols, dead projects, hackathon projects, avg TVL)
- Funding signal (hot/warm/cold)

## Searching VC Theses

Use `evm_copilot_search_vc_theses` for semantic search across 54 curated investment theses:

```
evm_copilot_search_vc_theses(query="stablecoins payments")
```

Coverage: a16z Crypto, Paradigm, Dragonfly, Multicoin Capital, Variant Fund, Galaxy Digital, Polychain Capital, Electric Capital, Coinbase Ventures, Delphi Digital, Messari.

## Getting VC Details

Use `evm_copilot_get_vc` for a firm's profile and portfolio:

```
evm_copilot_get_vc(slug="a16z-crypto")
evm_copilot_get_vc(slug="paradigm", category="DEX")
```

Available slugs: a16z-crypto, paradigm, dragonfly, multicoin-capital, variant-fund, polychain-capital, electric-capital, galaxy-digital, coinbase-ventures, sequoia-crypto, delphi-digital, messari

## When to Use

- User asks "who's funding X", "which VCs invest in Y"
- User wants to know if VCs are interested in a category
- Part of idea validation (funding signal adds context to gap analysis)
