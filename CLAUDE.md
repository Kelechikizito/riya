# riya

Foundry (Solidity) contracts in `src/`, `script/`, `test/`; Next.js app in `frontend/`.

## Commits

When asked to commit, split the work into **atomic commits** — one logical change
per commit, each independently revertable and each leaving the tree buildable.
Never lump unrelated changes into a single commit.

- Stage per-commit with explicit paths (`git add <paths>`), not a blanket `git add -A`.
- Separate contract changes, frontend changes, test changes, and config/dependency
  bumps into their own commits.
- Message format: `<type>(<scope>): <imperative summary>` — e.g.
  `feat(vault): add withdraw fee cap`, `test(vault): cover zero-amount deposit`,
  `chore(deps): bump OZ contracts`.
- Run `git status` before staging and confirm nothing secret is included
  (`.env` is gitignored — keep it that way).
- Push only when explicitly asked.

## Hackathon Context

This project is a **Creditcoin hackathon** submission. Judges score on five criteria:

| Criterion | What judges look for |
|---|---|
| **User Base Expansion** | Strong potential to grow the ecosystem's user base |
| **Technical Alignment** | Deep technical integration and alignment with the Creditcoin ecosystem |
| **Product Vision** | An innovative, practical, and compelling product roadmap |
| **Execution Capability** | A clear execution plan supported by a capable team |
| **Proven Models** | The ability to effectively apply proven business and technical models |

### How to apply these

Treat the five criteria as the standing rubric for every design, scoping, and
prioritisation decision — not just for the final submission write-up.

- When proposing or expanding a feature, state which criteria it advances and
  which it does not. A feature that serves none of them is scope to cut.
- **Technical Alignment is the load-bearing one for a Creditcoin submission.**
  Prefer designs that use Creditcoin-native primitives (ASC / Attestcoin
  contracts, the Block Prover Precompile, native cross-chain query verification)
  over generic EVM patterns that would run anywhere. "Could this ship on any
  L2 unchanged?" is a red flag, not a feature.
- Favour **proven models applied to a new substrate** over unproven novelty —
  judges reward recognisable business/technical patterns adapted to Creditcoin,
  not invented-from-scratch mechanisms.
- Scope to what is demonstrably buildable in the hackathon window. Execution
  Capability is judged on a *credible* plan, so prefer a narrow working vertical
  slice over a broad partially-working one.

### Hard constraint: readability only

**Writability is off the table for this build.** Per Creditcoin's docs, writability
"is undergoing 3rd party testing and audits" and is not yet released on Creditcoin
testnet. Treat it as unavailable, not as a stretch goal.

This means every idea must produce its value from the **readability** direction
alone: prove a source-chain transaction or event on Creditcoin via the Block
Prover Precompile (`0x0FD2`), then execute business logic on Creditcoin with the
verified data. Nothing can depend on pushing a verified message back out to
another chain.

When evaluating or expanding an idea:

- Reject or reshape any design whose payoff needs the outbound leg. A "round
  trip" story (prove inbound → act → write back) collapses to its inbound half.
- Say so explicitly and early when an idea silently assumes writability, rather
  than designing around it and discovering the gap later.
- Look for designs where **the destination state living on Creditcoin is the
  point**, not a waypoint — e.g. an asset, score, credential, or position that
  is natively useful on Creditcoin, so never leaving is a feature rather than a
  truncation.
- Writability may still appear in the *roadmap* as a future phase (Product
  Vision rewards a credible forward path), but never in the demo or the
  submission's critical path.

### Ask, don't assume

When an idea's feasibility against these criteria is genuinely unclear, ask
deliberate, specific questions rather than filling the gap with assumptions.
Good questions target: who the first 100 users actually are and why they show
up, which Creditcoin primitive the design depends on, what the demo shows at
submission time, and which proven model is being adapted.
