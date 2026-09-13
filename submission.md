# Riya

**Put dollars to work on Ethereum, borrow against them on Creditcoin, and let the yield repay the loan. No bridge, no oracle, no trusted relayer.**

## The problem

Self-repaying loans work. Alchemix proved it: deposit collateral, borrow against it, and let the yield retire the debt while you do nothing.

They only work on one chain at a time. The lender has to *see* the yield arrive, and a contract on Creditcoin cannot see an Ethereum transaction. Today that gap is closed by bridges and oracles — a multisig, a committee, or a price feed you have to trust. Each one is a party that can lie, stall, or be drained.

So the yield stays on the chain that earns it, and the credit exists nowhere.

## What Riya does

Ada has $1,000 of USDC and wants cash without selling.

1. **She deposits.** $1,000 goes into `RiyaEscrow` on Ethereum, which puts it straight into Aave V4. The escrow keeps no accounting of its own — it takes custody, emits one event, and that is the entire contract.
2. **The deposit is proven.** A permissionless worker fetches an inclusion proof and calls `RiyaASC.submit` on Creditcoin. Creditcoin re-checks the Ethereum block itself through the Block Prover Precompile at `0x0FD2`. No committee sits in between.
3. **She borrows $100.** New addresses open at a 10% limit and mint rUSD — an ordinary ERC-20 any Creditcoin wallet or contract accepts.
4. **The position earns.** Aave pays roughly 5% a year. Because Aave positions rebase silently, `harvest()` pulls the profit out in a real transaction, turning continuous interest into a discrete, provable fact.
5. **Each harvest is proven and retires debt.** Creditcoin verifies the harvest the same way it verified the deposit, takes a 15% fee, and spreads the rest across open positions. Ada's debt falls. She signs nothing.
6. **Her limit rises.** Only yield-retired debt moves the credit score, so the ladder measures productive collateral rather than activity. It runs 10% → 20% → 30% → 40% → 50%.
7. **The debt reaches zero.** Ada never repaid a cent.

## Why this needs Creditcoin

**The chain verifies the proof, not a committee.** `RiyaASC` calls the Block Prover Precompile directly. A bridge asks you to trust its validators; here Creditcoin re-runs the inclusion check itself. Take the precompile away and there is no way for the loan to learn that its collateral earned anything — the product stops existing rather than getting slower.

**Three checks the precompile does not make.** It answers one question: is this transaction in a real block? It does not say the transaction succeeded, that you have not already acted on it, or who emitted the logs inside it. `submit` adds all three, and dropping any one makes the protocol drainable:

| Check | The attack it closes |
| --- | --- |
| Replay key from chain, height, root and tx index | Replaying one real harvest until every borrower's debt hits zero |
| `receiptStatus == 1` | A reverted transaction still sits in a block and still proves cleanly |
| `log.address_` pinned per event | Anyone can deploy a contract emitting `TokensHarvested` with a value of one billion |

**The emitter pin is demonstrated, not asserted.** Event signatures are public, so anyone can forge an event and obtain a *genuine* Attestcoin proof for it. `make attack` deploys a hostile contract on live Sepolia, emits a forged `TokensHarvested`, and carries a real proof to `RiyaASC`. Every cryptographic check passes. It is rejected on `log.address_` — the one field a forger cannot control.

**Nothing waits on writability.** Every proof travels inbound. Creditcoin's outbound leg is still in third-party audit, and no part of this product needs it. The position living on Creditcoin is the point, not a waypoint.

**The credit score cannot be bought.** Cash repayment deliberately does not count toward the score. Borrow $100 and repay $100 on a loop and the score stays at zero, because only proven yield moves it.

## It is live on testnet

**Creditcoin Testnet (chain 102031)**

| Contract | Address |
| --- | --- |
| LoanLedger | [0x551904f44630B7C2ac9BBf81db795928Cc329E86](https://creditcoin-testnet.blockscout.com/address/0x551904f44630B7C2ac9BBf81db795928Cc329E86) |
| RiyaASC | [0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7](https://creditcoin-testnet.blockscout.com/address/0xce0c01B9c2E407af328eB25D06aea0f1929aaBC7) |
| RiyaUSD | [0x194b050678eb50923b84fE5aDC8E6f8176D43335](https://creditcoin-testnet.blockscout.com/address/0x194b050678eb50923b84fE5aDC8E6f8176D43335) |

**Ethereum Sepolia**

| Contract | Address |
| --- | --- |
| RiyaEscrow | [0xEDe17e550D36597CA497356DBE2CfCebC876b72e](https://sepolia.etherscan.io/address/0xEDe17e550D36597CA497356DBE2CfCebC876b72e) |
| AaveV4Adapter | [0x83142d63752E09490c4FfCd2482568a7c8618bFb](https://sepolia.etherscan.io/address/0x83142d63752E09490c4FfCd2482568a7c8618bFb) |

## Proof it ran

A complete cycle on live testnets. Every row is independently verifiable.

| Step | Chain | Transaction |
| --- | --- | --- |
| Deposit into the escrow | Sepolia | [0x5a6b48…a4eb](https://sepolia.etherscan.io/tx/0x5a6b48219b8a7f47605a0a03d41bf2858bd04ad6d0fa8c8bf4efc775fcc6c63b) |
| That deposit proven, collateral credited | Creditcoin | [0x2d3ee3…c080](https://creditcoin-testnet.blockscout.com/tx/0x2d3ee358f756371e3630dd2b4afe91268b8d6acbdcfda722550893c79d2cc080) |
| Borrow rUSD against it | Creditcoin | [0xd943f5…469e](https://creditcoin-testnet.blockscout.com/tx/0xd943f5685c23d7b173513826a24a8fbfddb907cb0f80f52a5e261e0ac534469e) |
| Harvest the Aave yield | Sepolia | [0x4f08ec…0c00](https://sepolia.etherscan.io/tx/0x4f08ec2bd9b2354da4512309a84871649ab0759d73321dea2f2efa15f0f10c00) |
| That harvest proven, yield distributed | Creditcoin | [0x12d23f…c861](https://creditcoin-testnet.blockscout.com/tx/0x12d23f5fb72f3a89cd23a01429d4e93ae90a2744680e62e1151dbf3f2e36c861) |
| **Debt retired by proven yield** | Creditcoin | [0x5b661c…3fed](https://creditcoin-testnet.blockscout.com/tx/0x5b661cbd092ee97d8292764538d01c0fbe4558388b872e43547bda6ac4923fed) |

**Thirteen proofs have been verified on Creditcoin so far** — six deposits and seven harvests — none of them carried by a bridge or a relayer with special rights.

The live ledger state:

| | |
| --- | --- |
| Total collateral | $5,100.00 |
| Debt retired by proven yield | **$300.00** |
| Credit score | **30**, up from 0 |
| Borrow limit | **20%**, one tier up the ladder |
| Protocol fees accrued | $105.00 |

The credit score is not a mock. It moved because proven yield retired real debt.

## Engineering

**179 tests across 15 suites**, including fuzz suites that state properties rather than examples: settling twice changes nothing; a deposit never raises the credit score; debt never exceeds half the collateral at any tier; no impostor contract can create collateral or distribute yield; a reverted source-chain transaction never applies.

Ten of those tests run against Creditcoin Testnet over RPC and fail if the live chain registry disagrees with the hardcoded keys. The Aave adapter is tested against the real Aave V4 Spoke on an Ethereum Mainnet fork.

The deploy is reproducible: three contracts with mutually circular constructor pins, addresses predicted with `vm.computeCreateAddress` and each prediction asserted afterwards, plus a chain-key check against the Chain Info Precompile before any gas is spent.

## Known limitations, stated plainly

**Protocol fees accrue but cannot be collected.** `s_protocolFees` is a claim on USDC held in the Ethereum escrow, and paying it out needs the outbound leg. A fix exists that needs no writability — mint the fee as rUSD against the 15% of each harvest that lands undistributed — but it is not built.

**If Aave is impaired, the protocol absorbs it.** Yield is holdings minus principal. If the reserve takes a loss, collateral shrinks while the Creditcoin debt does not, and there is no liquidation path. The designed answer proves the shortfall the same way yield is proven and socialises it after the fee buffer absorbs what it can. Designed, not built.

**Proofs are not instant.** A deposit is credited once its Ethereum block is attested, not the moment it lands. Measured at three to four minutes on testnet. That latency is the honest cost of not trusting a bridge.

## Stack

Solidity 0.8.30 and Foundry. Aave V4 as the yield venue. `@gluwa/usc-contracts` for the precompile interfaces and `@gluwa/usc-sdk` for proof building. TypeScript, ethers v6 and SQLite for the readability worker and keeper. Next.js 16, wagmi and viem for the frontend, with Playwright driving end-to-end tests against the live deployment.

## Links

- **Code:** https://github.com/Kelechikizito/riya
- **Build walkthrough:** https://github.com/Kelechikizito/riya/tree/main/walkthrough
