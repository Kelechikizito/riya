Idea 1 — Cross-chain credit score → undercollateralized lending ⭐
Aggregate a wallet's real repayment history across Ethereum/Base/Arbitrum (batch-verify up to 10 repayment/liquidation events under one continuity proof), compute a portable credit attestation on Creditcoin, then use writability to push a borrow limit back to pools on other chains.
Why it wins: judges are Creditcoin & Credit Labs — this is their entire thesis. Credit history is genuinely fragmented across chains, so cross-chain isn't decorative. Hits DeFi and RWA. Uses batch + both directions.

Idea 2 — Atomic cross-chain liquidation guard
Synchronous verification means a Creditcoin position can verify a collateral-price or withdrawal event on another chain inside the same transaction it liquidates. Impossible with request/callback oracles.
Why it wins: the sharpest demonstration of the one-block property. Risk: narrow demo, harder to make visually compelling.

Idea 3 — RWA invoice financing
Verify a stablecoin settlement event on Ethereum → release/settle invoice financing on Creditcoin → writability confirms payoff back to the payer's chain.
Why it wins: "real world" is literally the hackathon slogan; RWA track is less crowded than DeFi.

Idea 4 — DePIN uptime settlement
Devices emit cheap attestations on a low-cost chain; batch-verify 10 at a time; settle rewards on Creditcoin.
Why it wins: DePIN is likely the emptiest track. Risk: needs fake device data, which weakens the demo.

My recommendation: Idea 1. It's the only one where the judges' own product thesis and the protocol's unique capability point at the same build, and it degrades gracefully — if writability proves fiddly, a read-only credit-attestation demo still stands on its own.

Two things would sharpen this: what does riya currently mean/do (the repo has Foundry contracts already — what's in src/?), and which track pulls at you. Want me to read src/ and tell you what you've already got to build on?
