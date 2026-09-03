// // The readability worker — the only path anything reaches Creditcoin by: watches Ethereum for `RiyaEscrow`
// // and `AaveV4Adapter` events, waits for attestation, proves them, and feeds `RiyaASC.submit()` in block order.

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

import { JsonRpcProvider } from "ethers";
import { chainInfo, blockProver, proofProvider } from "@gluwa/usc-sdk";
import "dotenv/config";

async function proveTransaction(txHash: string) {
  //  STEP 1: RESOLVE CHAIN KEY
  const chainKey = 1; // Ethereum Sepolia on CC3 Testnet

  // STEP 2: GET PROVIDERS, PROVER AND PROOF BUILDER
  // Ethereum Sepolia RPC
  const sourceProvider = new JsonRpcProvider(process.env.ETH_SEPOLIA_RPC_URL);
  // Creditcoin CC3 Testnet (CC3 Mainnet only once you are ready for production)
  const creditcoinProvider = new JsonRpcProvider(
    process.env.CREDITCOIN_RPC_URL,
  );

  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(
    creditcoinProvider,
  );
  const prover = new blockProver.PrecompileBlockProver(creditcoinProvider);
  const proofBuilder = new proofProvider.service.ProofBuilder(
    chainKey,
    "https://prover.cc3-testnet.creditcoin.network",
  );

  // STEP 3: FIND BLOCK AND WAIT FOR ATTESTATION
  const tx = await sourceProvider.getTransaction(txHash);
  await proofBuilder.waitUntilHeightAttested(chainKey, tx!.blockNumber!);

  // STEP 4: GENERATE PROOF AND VERIFY API
  const result = await proofBuilder.getProof(txHash);
  if (!result.success || !result.data) {
    throw new Error(`Proof generation failed: ${result.error}`);
  }
  const {
    chainKey: ck,
    headerNumber,
    txBytes,
    merkleProof,
    continuityProof,
  } = result.data;

  // STEP 5: VERIFY ON-CHAIN
  const verified = await prover.verifySingle(
    ck,
    headerNumber,
    txBytes,
    merkleProof,
    continuityProof,
  );
  console.log("Proof verification:", verified ? "SUCCESS" : "FAILED");

  return verified;
}
