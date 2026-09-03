// // The readability worker — the only path anything reaches Creditcoin by: watches Ethereum for `RiyaEscrow`
// // and `AaveV4Adapter` events, waits for attestation, proves them, and feeds `RiyaASC.submit()` in block order.

import { JsonRpcProvider } from "ethers";
import { chainInfo, blockProver, proofProvider } from "@gluwa/usc-sdk";

// // Typical Worker Transaction Flow
// // The worker automates the following process:
// // Monitor source chain: The worker constantly monitors the source chain contract for events (e.g., TokensBurnedForBridging events).
// // Wait for attestation: When an event is detected, the worker waits for the block containing the event to be attested on Creditcoin.
// // Generate proofs: The worker can generate Merkle and continuity proofs via the Proof Builder service.
// // Call ASC contract: The worker calls the ASC contract with the proofs and encoded transaction data. The ASC contract verifies the proofs synchronously and executes business logic immediately.
// // Handle results: The worker can listen for events from the ASC contract to confirm successful execution.
// // All of this happens automatically - the user only needs to sign the initial source chain transaction.

// // From CreditCoin Official docs:
// Keeping this in mind, the main goal of an Offchain Worker should always be robustness. This includes:
// Retaining stored records of events in progress in the event of a Worker shutdown // @question: should we then integrate a database, preferreably a postgres database?
// Catching up with any event that might have been missed as a result of an unexpected shutdown
// Avoiding submitting multiple ASC calls for the same event (replay protection is handled by the ASC contract, but workers should also track processed events)
// Following multiple source chain nodes to listen for events in case a node experiences issues
// Retrying failed proof generation or ASC calls in case they fail. A call can fail for many reasons: for example, the Proof Builder services might be experiencing downtime or connectivity issues, or the ASC contract call might fail due to network issues
