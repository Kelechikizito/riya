- On the Creditcoin network, apps and services use Attestcoin Smart Contracts (ASC), contracts that interact with the Attestcoin Protocol, to execute business logic spanning any number of chains. Operating across many chains simultaneously integrates their isolated pools of information and capital, opening up new powerful business use cases.
- The block prover precompile is a runtime component at address 0x0FD2 that supports Attestcoin Protocol's readability by verifying cross-chain data within Creditcoin transactions. It validates two proofs: a Merkle proof for transaction inclusion in a block, and a continuity proof linking that block to an on-chain attestation or checkpoint via a chain of block digests. The precompile runs as compiled Rust code, avoiding EVM interpretation overhead. Verification is synchronous: given transaction data, a Merkle proof, and a continuity proof, it checks that the Merkle root matches the block in the continuity chain, that the chain ends at a valid attestation/checkpoint, and that block digests are correctly linked via cryptographic hashing. Two functions are available: verify() (only view, no events) and verifyAndEmit() (state-changing, emits TransactionVerified events). ASC contracts use this to verify cross-chain events and transactions in a single transaction, replacing external proof systems and off-chain services.

## Outcome for Builders

### Readability

The net effect of readability is that third-party builders can create contracts on Creditcoin which have secure, trustless access to verified data from other chains. Attestcoin smart contracts can verify that specific transactions occurred on external blockchains (like Ethereum) and then react to those verified events by executing business logic on Creditcoin.

For example, a bridge contract could:

Verify that a user burned or locked up ETH on Ethereum (by verifying the burn transaction using the precompile)

Based on that verified proof, mint equivalent wrapped tokens on Creditcoin

Builders can leverage these properties to create attestcoin smart contracts which support their own custom cross-chain DApp business logic, enabling trustless cross-chain applications without relying on centralized oracles or intermediaries.

#### Provisioning Steps

1-2. Attestors listen for new source chain blocks, vote on attestations, and store those attestations on-chain. These are used later by the Block Prover Precompile to prove source chain transactions.

3a. Meanwhile, dApp builders listen for the emission of events on the source chain which are relevant to their dApp.

3b. When an event is detected, dApp builders send a request to the proof generation server asking for proofs of the transaction containing the target event.

3c. The transaction and proofs are submitted to a dApp's Attestcoin Smart Contract, which forwards them to the Block Prover Precompile.

4. The Block Prover Precompile verifies merkle and continuity proofs, signaling whether or not the source chain transaction is valid

5. The dApp's Attestcoin Smart Contract decodes the verified transaction, extracting the relevant event. It then uses the event to trigger dApp logic and emit events.

#### Continuity Proofs

A continuity proof is one of two key proofs needed by Attestcoin Protocol Readability to securely move data from one chain to another. It organizes source chain blocks into a segment so that each block hash links to the next. Together these hashes/digests ensure that attestation n + 1 is always a valid descendant of attestation n

Why do we need continuity proofs? Why can't attestors simply record consensus about every block? The answer has two parts:

On-chain Storage: Storing attestations for every source chain block on our Creditcoin chain would be too expensive, especially for chains like Solana that produce blocks frequently.

Attestor Network Load: The Attestor network must perform expensive signing, hashing, p2p gossip, and tx submission for every attestation it produces. We make the Attestor networks more resilient and efficient by not attesting to every block.

To solve both problems, we produce attestations at larger intervals (e.g., every 10 or 100 source chain blocks). Each attestation links to the previous one via digests. When there's a gap between attestations, a continuity proof fills it. This proof is a chain of digests of intermediate source chain blocks that:

Starts from the block immediately after the last finalized attestation

Ends at the block immediately before the new attestation

Proves each intermediate block links to the previous one via digests

Hash: A cryptographic hash is a deterministic mathematical function that takes an input of arbitrary size and produces a fixed-size output, called a hash value.

Merkle Tree: A Merkle tree is a balanced binary tree of cryptographic hashes that enables efficient and secure verification of integrity of large data sets.

With the tree’s Merkle root and a small subset of hashes (a Merkle proof), one can efficiently verify whether a given piece of data is included in the set without revealing or re-hashing all the data. This property allows us to efficiently determine whether a part of a transaction is contained in the Merkle tree for a given block.

Root (Merkle Root): A Merkle root is the single cryptographic hash at the top of a Merkle tree. It uniquely summarizes all the data beneath it, allowing us to rapidly verify the integrity of all the data stored in that tree. Root in code:

`let root = eth::starknet_pedersen_mmr(&block_data);`

Digest: Another term for any output from a hash function. In the context of the Attestcoin Protocol, a digest usually describes the hash output uniquely identifying a block or attestation. The digest of a block is derived by hashing its block number, Merkle root, and previous digest. Digest in code:

`let digest = Self::hash_payload(&block_number.into(), &root, &prev_digest);`

Previous Digest: The previous digest of a block is just the digest of the block before it. We generate each new block digest using the previous digest.

#### Transaction Proving

The query-prove-verify process enables Attestcoin Smart Contracts (ASC) to trustlessly verify and use data from source chains. The process consists of four main phases:

- Query Phase: Identifying the target transaction for verification
- Proof Generation Phase: Creating Merkle and continuity proofs
- Verification Phase: Cryptographic verification of the proofs
- Data Extraction Phase: Extracting transaction data from verified bytes

Proof Types

To prove that a transaction occurred on a source chain, the system uses two complementary cryptographic proofs:

Merkle Proofs: Prove that a specific transaction x is part of block y

Continuity Proofs: Prove that block y is part of the finalized source chain

Together, these proofs provide cryptographic certainty that a transaction actually occurred on the source chain, enabling trustless cross-chain applications.

Where are proofs generated, and where are they used?

Prover Server (off-chain): Generates Merkle and continuity proofs on-demand

Block Prover Precompile (on-chain): Verifies proofs synchronously and extracts data

---

Full Process Summary

A dApp team or end user identifies a target transaction they want to verify. This is usually done via a Oracle Query Worker that listens for source chain events and submits proving requests. Alternatively, for teams that don't want to stand up their own worker, paid 3rd party relayer submission of readability queries will be available in the near future.

The Oracle Query Worker requests proofs from the Prover Server via an endpoint like proof-by-tx/{chain_key}/{tx_hash} .

The Prover Server retrieves attestation data from Creditcoin and fetches source chain blocks.

The Prover Server then uses attestation and block data to construct a continuity proof and a merkle proof for the target tx. These proofs are returned to the Oracle Query Worker.

The Oracle Query Worker submits the target tx and its proofs to Creditcoin via a Attestcoin Smart Contract call. There, the tx and proofs are passed to the Block Prover Precompile

The Block Prover Precompile verifies both proofs synchronously, flagging whether the target tx is valid or invalid.

Once verified, the transaction data can be decoded and used for dApp business logic

---

- Continuity proofs for queries are cryptographic proofs that link the queried source chain block to an on-chain attestation or checkpoint, establishing that the block is part of the finalized source chain. This is one of the two essential proving steps used by the Attestcoin Protocol to achieve trustless cross-chain data readability. `digest[i] = hash(blockNumber[i], merkleRoot[i], digest[i-1])` `struct ContinuityProof {
    lowerEndpointDigest: bytes32,  // Digest of block (queryHeight - 1)
    roots: bytes32[]            // Array of Merkle roots
}`
- Attestcoin Protocol Readability uses Merkle proving to determine whether a transaction is included in a given block. It is the second of two key proofs that certify oracle results. Attestcoin readability uses standard Merkle trees (Keccak-256 hashing). Merkle proofs are verified natively by the precompile, providing fast and efficient verification without requiring specialized proof systems.
- Continuity Proof Length (Large effect): For each block in a continuity proof, the Block Prover Precompile must perform a hashing operation to calculate a digest. All these hashing ops cost gas. For historical transactions, continuity proofs can be quite long (Eg: 1000 blocks). If you aren't already familiar with what a continuity proof is, see continuity proving for queries.
- While not strictly a part of the verification process, transaction decoding is still a necessary step for Attestcoin Readability. For almost all transactions the cost of decoding is negligable. But a few outliers make this cost potentially noteworthy. Transaction types to avoid; A single transaction in which contracts circularly call each-other 1000's of times. Transactions which bundle state updates for layer 2 rollup chains. If you do happen request verification and decoding of very large transactions repeatedly, then the cost will add up. Estimated cost for 1 maximal decoding workload is 0.0375 CTC.
- Cost ≈ (base tx cost) + (hash op cost) · (continuity hash count). Based on it the approximate costs are: CTC Cost ≈ 2.3×10−5 + 2.9×10−7 \* (continuity hash count)
- The cost of Attestcoin Protocol Readability is currently quite low, facilitating as much traffic as desired. To future proof against the potential of rising readability costs, try to make verification requests for transactions when they are recently finalized. This will reduce average continuity proof length by a factor of 10-100x.

### Writability

The net effect of writability is that Attestcoin Smart Contracts can act beyond Creditcoin: a contract can publish a message that, once validated by attestors, is delivered to a contract on a destination chain and triggers execution there. Builders get verified outbound reach without deploying bridge infrastructure of their own.

Continuing our bridge contract example, with writability the bridge contract could:

Send a writability message declaring that wrapped ETH tokens were burned by a user

Receive the signed and verified message on Ethereum, releasing the original locked ETH to the user

Combined with readability, this closes the information loop: builders can prove inbound events, act on them, send verified instructions back out, and even receive delivery confirmation.

## DAPP BUILDER INFRA

The Attestcoin Protocol is intended for use by dApp builders. However, in order to use the oracle effectively dApp teams will need to set up some infrastructure of their own.

- Source Chain Smart Contract: Deployed on source chain like Ethereum, Sepolia. Key requirements:
  - Emit events with the data the dApp needs to verify
  - Events should be structured to allow easy extraction of relevant fields
  - Contract should handle any logic that must happen on the source chain (e.g., burning tokens)
  - Example: To support a token bridge dApp the source chain smart contract might be an ERC20 contract that emits TokensBurnedForBridging events.
- Attestcoin Smart Contract (ASC): Deployed on Creditcoin. A smart contract that verifies cross-chain transaction data using the Native Query Verifier Precompile (address 0x0FD2) and then executes the dApp's business logic. Key responsibilities:
  - Receives proofs (Merkle and continuity) and encoded transaction data from workers via a smart contract call
  - Calls the Native Query Verifier Precompile on Creditcoin to verify proofs synchronously
  - Extracts transaction/event data from verified transaction bytes
  - Executes dApp Business Logic or calls separate business logic contract using the verified data
  - Example: In a token bridge dApp, the ASC interprets oracle-provided data corresponding to the burn event on the source chain.
- dApp Business Logic Smart Contracts: Deployed to Creditcoin
  - Separated pattern: ASC and business logic can be kept in separate contracts. The ASC contract handles verification and then calls separate business logic contracts after verification succeeds. This pattern provides better modularity and is recommended for complex dApps.
  - Key responsibilities: Store dApp state (e.g., token balances, user data), Implement dApp-specific logic (e.g., minting tokens, updating balances), Provide functions that can be called by their ASC contract, Enforce access control (typically only allow calls from their ASC contract).
  - Example: For a token bridge, this might be an ERC20 contract on Creditcoin that mints tokens when the ASC contract verifies a burn event from the source chain.
- Readability Worker: Deployed 💻 offchain. An off-chain service that monitors source chain events and automatically submits verified transactions to their ASC contract. Key responsibilities:
  - Listen for events from the source Chain Smart Contract
  - Wait for the block containing the event to be attested on Creditcoin
  - Use the Proof Builder service to get Merkle and continuity proofs
  - Call the ASC contract with the proofs and encoded transaction data
  - Retry failed transactions, track processing status, prevent duplicates etc

With all four components in place:

User signs transaction on source chain → emits event. Oracle Worker detects event → waits for attestation → fetches proofs → calls ASC. ASC Contract verifies proofs → extracts data → calls Business Logic Contract. Business Logic Contract executes dApp logic → updates state

This enables seamless cross-chain interoperability where a transaction on one chain automatically triggers dApp logic execution on Creditcoin!
