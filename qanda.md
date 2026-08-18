# Q and A

## 1

### Q

Does an Attestcoin proof for an EVM source chain cryptographically commit to the transaction receipt as well as the transaction itself? Specifically, can a Creditcoin contract safely use receipt.status and specific event logs as verified data? If not, what is the recommended way to prove that a source transaction succeeded rather than reverted?

Can a Creditcoin contract obtain a cryptographically attested current height or timestamp of an external chain such as Sepolia, or prove that a particular source-chain block exists without referencing a specific transaction?

What exactly is encodedTx in the EVM proof flow: the raw signed Ethereum transaction, or an Attestcoin-specific encoding that includes transaction and receipt data? Can the verifying contract deterministically derive the canonical Ethereum transaction hash from it?

Is Attestcoin currently bidirectional? Can a verified decision or message originating on Creditcoin be consumed trustlessly on an external EVM chain such as Sepolia?

### A

Does an Attestcoin proof for an EVM source chain cryptographically commit to the transaction receipt as well as the transaction itself? Specifically, can a Creditcoin contract safely use receipt.status and specific event logs as verified data? If not, what is the recommended way to prove that a source transaction succeeded rather than reverted?

Transaction fields and its logs data is verified and available.

Can a Creditcoin contract obtain a cryptographically attested current height or timestamp of an external chain such as Sepolia, or prove that a particular source-chain block exists without referencing a specific transaction?

Attestcoin intentionally has an amount of blocks behind latest height of source chain, to avoid building the attestation chain before the re-orgs happen.

What exactly is encodedTx in the EVM proof flow: the raw signed Ethereum transaction, or an Attestcoin-specific encoding that includes transaction and receipt data? Can the verifying contract deterministically derive the canonical Ethereum transaction hash from it?

Transaction and receipt data is verified and available. Deterministically derving the canonical Ethereum transaction hash could be done but we don't currently provide tooling/helpers to do so.

Is Attestcoin currently bidirectional? Can a verified decision or message originating on Creditcoin be consumed trustlessly on an external EVM chain such as Sepolia?

Writability is currently in final phase of development and will provide the type of functionalities referred to in the question. Although writability is out of scope for this Hackathon, if it's necessary for your build, you may consider sending transactions on source chain without Attestcoin features, and those will then be verified by attestors.
