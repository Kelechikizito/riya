# Creditcoin Environments — values that bind Riya

Extracted from docs.creditcoin.org/environments{,/mainnet,/testnet}, fetched
2026-08-28. Values quoted from the docs; anything I could not confirm is marked
as such rather than guessed.

## Chainkeys are per-Creditcoin-network

Each Creditcoin network has its own attested-chain registry. The same chainkey
means a different source chain depending on which network the ASC sits on, and
the testnet registry holds **two** chains:

| Creditcoin network | Source chain | Chainkey | Genesis block |
|---|---|---|---|
| Creditcoin Testnet (`102031`) | Ethereum Sepolia | `1` | `0` |
| Creditcoin Testnet (`102031`) | Ethereum Mainnet | `3` | `0` |
| Creditcoin Mainnet (`102030`) | Ethereum Mainnet | `1` | `0` |

(The testnet page labels its table "Supported Mainnet Chains" — a docs
copy-paste, not a mistake in the values. Verified against the raw markdown at
`docs.creditcoin.org/environments/testnet.md`.)

Two consequences for `RiyaASC`:

1. **The `chainKey != I_CHAIN_KEY` pin is load-bearing right now, not
   defensively.** On Creditcoin Testnet — where the demo runs — an unpinned ASC
   accepts proofs from Ethereum Mainnet as readily as from Sepolia. Since
   `mintFromQuery` takes `chainKey` from an untrusted relayer, and a contract
   can hold the same address on both chains (same deployer nonce, or CREATE2),
   the `I_ESCROW_CONTRACT` check alone does not save you. This is a live attack
   surface on the demo chain, not a roadmap hypothetical.
2. **`I_CHAIN_KEY` is `1` in both intended deploys**, but for different reasons:
   `1` = Sepolia on Creditcoin Testnet, `1` = Ethereum Mainnet on Creditcoin
   Mainnet. Do not read that coincidence as "the key is always 1" — it is a
   per-network constructor argument.

`0` appears in neither registry, so a zero chainKey means an uninitialized
immutable and should revert in the constructor.

### Side note worth weighing

Creditcoin Testnet can read **Ethereum Mainnet** (chainkey `3`). A demo could
therefore prove real Mainnet activity while paying only testnet gas on the
Creditcoin side. Relevant if Riya's demo would be more convincing reading live
Mainnet positions than synthetic Sepolia ones.

## Creditcoin Testnet — the demo target

- Network name: `Creditcoin Testnet`, `--chain testnet`
- **EVM chain ID: `102031`**
- Substrate chain ID: `0xfc4ec97a1c1f119c4353aecb4a17c7c0cf7b40d5d660143d8bad9117e9866572`
- RPC (WSS): `wss://rpc.cc3-testnet.creditcoin.network` — no HTTP endpoint is
  documented, which matters because `forge script` wants HTTP
- EVM explorer (Blockscout): `https://creditcoin-testnet.blockscout.com/`
- Substrate explorer (Subscan): `https://creditcoin3-testnet.subscan.io/`
- Currency: `tCTC`
- Verify precompile: `0x0000000000000000000000000000000000000FD2`
- ASC dashboard: `https://dashboard.cc3-testnet.creditcoin.network/`
- Proof Builder API: `https://prover.cc3-testnet.creditcoin.network/`
  (the page also shows `https://proof-gen-api.cc3-testnet.creditcoin.network/`
  — confirm which one the off-chain worker should call)
- Latest Docker image: `gluwa/creditcoin3:3.131.0-testnet`
- Minimum `@polkadot/api`: `16.1.1`
- Not documented: faucet URL, block time, testnet decoder contract address

## Creditcoin Mainnet — the production story

- Network name: `Creditcoin`
- **EVM chain ID: `102030`**
- RPC (WSS): `wss://mainnet3.creditcoin.network`
- EVM explorer (Blockscout): `https://creditcoin.blockscout.com/`
- Substrate explorer (Subscan): `https://creditcoin.subscan.io/`
- ASC dashboard: `https://dashboard.cc3-mainnet-usc.creditcoin.network/`
- Proof Builder API: `https://proofbuilder.cc3-mainnet-usc.creditcoin.network/`
- Decoder contract: `0x9D094C9f22B10FCf842c2fC6A0981630A4F94B5C`

## Open items for the build

1. **HTTP RPC.** Only WSS is documented for both networks. `forge script`
   deploys need an HTTP URL — find one or front the WSS endpoint.
2. **Testnet faucet.** Undocumented on the environments page; needed before any
   Creditcoin-side deploy.
3. **Proof Builder endpoint.** Two testnet URLs appear; the off-chain worker
   needs the right one.
4. **`foundry.toml`.** `[rpc_endpoints]` currently only has `mainnet_eth` and
   `sepolia_eth`. Add `creditcoin_testnet` (and later `creditcoin_mainnet`)
   once the HTTP endpoint is known. `bypass_prevrandao = true` is already set
   per Q10.
5. **Decoder contract.** Mainnet publishes one; the testnet equivalent is not
   on the page. `EvmV1Decoder` is imported as a library in `RiyaASC`, so
   confirm whether the deployed decoder is needed at all.
