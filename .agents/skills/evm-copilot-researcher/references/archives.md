# Research Archives

## Searching Archives

Use `evm_copilot_search_archives` to search across 1,500+ curated research documents:

```
evm_copilot_search_archives(query="account abstraction ERC-4337", depth="standard")
```

## Sources

- **EIPs/ERCs** (895 docs) — Ethereum Improvement Proposals
- **Vitalik's Blog** (154 posts) — Vitalik Buterin's essays
- **ethresear.ch** (450 posts) — Ethereum research forum
- **EF Blog** (9 posts) — Ethereum Foundation blog

## Search Depth

- `shallow` — Vector search only. Fast.
- `standard` — Vector + chunk full-text search. Good balance.
- `deep` — Full cascade: vector, chunk FTS, document FTS. Most thorough.

## Reading Full Documents

After finding a relevant document, read the full content:

```
evm_copilot_get_document(documentId="uuid-here", page=1)
```

Documents are paginated (5000 chars per page).

## When to Use

- User asks about EIPs, Ethereum research, or protocol design
- Need to ground an analysis in foundational research
- Looking for technical context on a topic
