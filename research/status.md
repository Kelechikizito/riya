# riya — status recap

_Snapshot taken 2026-08-31, at commit `ecbc40c`._

**Pitch:** deposit USDC on Ethereum → earns Aave yield → yield is *proven* onto
Creditcoin via the Block Prover Precompile → it pays down a loan taken out there.
Alchemix's self-repaying loan, split across two chains. Readability-only,
Ethereum-only source chain.

**Architecture rule:** Ethereum holds money and states facts (two dumb contracts,
no policy). Creditcoin decides what they mean (collateral, fee, score, LTV, debt).
Only a proof crosses.

---

## Where the build stands

### Ethereum leg — essentially done

- **`AaveV4Adapter`** (222 LoC) — supply to Aave V4, principal/yield split,
  permissionless `harvest()` that pushes gross yield to the escrow *before*
  emitting. Frozen; no changes planned.
- **`RiyaEscrow`** (106 LoC) — custody only. `deposit()` → adapter → Aave, emits
  `TokensDepositedConfirmedByEscrow(user, assets)`.
- **`IYieldAdapter`** / **`IAaveV4Spoke`** interfaces in place.
- **`DeployRiyaSourceChain`** + **`HelperConfig`** — deploys the circular
  adapter/escrow pair via nonce prediction, with a prediction assertion.
- ✅ `forge build` clean; ✅ 2 mainnet-fork tests pass (deposit path + address
  prediction).

### Creditcoin leg — barely started

- **`RiyaASC`** (132 LoC) — errors, event-signature constants, immutables
  (`I_VERIFIER`, `I_CHAIN_KEY`, `I_ESCROW_CONTRACT`, `I_ADAPTER_CONTRACT`),
  constructor, and the replay key inside `submit`. That is all.
- **`LoanLedger`** — **does not exist.** No file.

### Frontend

Untouched Next.js starter — `page.tsx` is the default template.

### Watcher bot

Does not exist. No directory for it.

---

## What is left, in critical-path order

1. **`LoanLedger` on Creditcoin** (~160 LoC) — the biggest single gap. Collateral
   mirror, 15% fee, MasterChef `s_yieldPerShare` accumulator, `_settle()`,
   `score()`, `maxLtvBps()` ladder, `borrow()`, `onlyASC` guard — plus the
   dual-auth split: the ASC path and the direct user path authenticate
   separately from day one.
2. **Finish `RiyaASC.submit`** — the three security checks are all still missing:
   `verifyAndEmit`, `receiptStatus == 1`, and `_dispatch` with the per-event
   `log.address_` pin. Plus wire `I_LEDGER`.
3. **Sepolia deployability** — `MockAaveSpoke` does not exist (Aave V4 has no
   testnet deployment); `getSepoliaConfig` reads `MOCK_SPOKE` / `MOCK_RESERVE_ID`
   from `.env` and neither is set. `getAnvilConfig` still reverts (TODO
   checkpoint 9).
4. **Watcher bot** — listen for the two events, wait for Creditcoin attestation,
   build Merkle + continuity proofs, call `submit` in source-chain order.
5. **Creditcoin deploy script** + `deployment-eth.sh` (currently a 0-byte
   placeholder).
6. **Test suite** — the ~13-item checklist in `build-plan.md` is entirely
   unwritten (replay, reverted tx, impostor emitter, pro-rata split, fee split,
   borrow limits, score neutrality of `repay`).
7. **Frontend** — deposit / borrow / score dial / self-repay rate. Zero work done.

**Optional polish (post-demo):** `repay()` (~10 LoC), `selfRepayRateBps()` view
(~8 LoC), Position NFT (unresolved soulbound-vs-transferable decision),
`IYieldAdapter` seam extraction.

---

## Honest read on risk

- The **entire Creditcoin half is unbuilt**, and it is the half that carries
  Technical Alignment — the load-bearing judging criterion.
- **Sepolia has no Aave V4**, so the demo needs a mock spoke that does not exist
  yet. This blocks *every* end-to-end rehearsal, not just the final demo.
- The watcher bot is the one component with no code and no design document
  beyond a sequence diagram.

The demo shot — one `harvest()`, one proof, every borrower's debt falls at once —
needs items 1, 2, 3 and 4 all working. That is the whole remaining critical path.
