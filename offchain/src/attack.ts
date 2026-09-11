// The adversary's submitter.
//
// The worker refuses to carry a forged event, and rightly so — `worker --once` filters logs
// by the real escrow and adapter addresses before it will spend a proof. That is the correct
// production behaviour and exactly why it cannot stage this demo. An attacker is not bound by
// the worker's good manners: they build the proof themselves and submit it directly.
//
// So this program is deliberately hostile. It takes the transaction hash of a forged event,
// gets a genuine Attestcoin proof for it — the proof is real, because the transaction is real
// — and calls `RiyaASC.submit`. The whole point is that every cryptographic check passes and
// the contract rejects it anyway, on `log.address_`, which is the one field a forger cannot
// control. It should revert with `RiyaASC__NoRelevantLog`.
//
//   npm run attack -- <forged-tx-hash>
//
// A success here would be a critical bug. The expected, and only acceptable, outcome is the
// revert.

import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { blockProver, chainInfo, proofProvider } from "@gluwa/usc-sdk";

import { RIYA_ASC_ABI } from "./abi.js";
import * as config from "./config.js";
import { permanentError, replayKey } from "./worker.js";

async function main(): Promise<void> {
  const txHash = process.argv[2];
  if (txHash === undefined || !txHash.startsWith("0x")) {
    throw new Error("Usage: npm run attack -- <forged-tx-hash>");
  }

  const creditcoin = new JsonRpcProvider(config.CREDITCOIN_RPC_URL);
  // The worker's key funds this, because an attacker with tCTC is the threat model. Nothing
  // about being the worker is required to try this — that is the point.
  const signer = new Wallet(config.workerPrivateKey(), creditcoin);
  const asc = new Contract(config.riyaAscAddress(), RIYA_ASC_ABI, signer);

  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(creditcoin);
  const prover = new blockProver.PrecompileBlockProver(creditcoin);
  void prover;
  const proofBuilder = new proofProvider.service.ProofBuilder(config.CHAIN_KEY, config.PROVER_URL);

  console.log(`\nAttempting to prove forged transaction ${txHash} to RiyaASC.`);
  console.log(`Signer ${await signer.getAddress()} — a funded account, nothing privileged.\n`);

  const sourceProvider = new JsonRpcProvider(config.SOURCE_RPC_URLS[0]);
  const tx = await sourceProvider.getTransaction(txHash);
  if (tx === null || tx.blockNumber === null) {
    throw new Error(`${txHash} is not a mined Ethereum transaction.`);
  }

  console.log(`Waiting for Creditcoin to attest Sepolia block ${tx.blockNumber}...`);
  const bounds = await chainInfoProvider.getContinuityBounds(config.CHAIN_KEY, tx.blockNumber);
  console.log(`  attested: ${bounds.isAttested}  (latest bound ${bounds.childHeight})`);

  await proofBuilder.waitUntilHeightAttested(
    config.CHAIN_KEY,
    tx.blockNumber,
    config.worker.attestationPollMs,
    config.worker.attestationTimeoutMs,
    config.worker.extraDelayMs,
  );

  const result = await proofBuilder.getProof(txHash);
  if (!result.success || !result.data) {
    throw new Error(result.error ?? "proof builder returned no data");
  }
  const { headerNumber, txIndex, txBytes, merkleProof, continuityProof } = result.data;

  const key = replayKey(config.CHAIN_KEY, headerNumber, merkleProof.root, txIndex);
  console.log(`\nGot a valid proof. Replay key ${key}.`);
  console.log("The proof is genuine — the transaction really happened. Submitting anyway.\n");

  try {
    const submit = asc.getFunction("submit");
    const sent = await submit(headerNumber, txBytes, merkleProof, continuityProof);
    const receipt = await sent.wait();

    // Reaching here means a forged event moved riya's state. That is the failure this whole
    // exercise is meant to make impossible.
    console.error("ATTACK SUCCEEDED. This is a critical bug.");
    console.error(`  tx ${receipt?.hash} applied a forged event to the ledger.`);
    process.exit(1);
  } catch (error) {
    const named = permanentError(error);
    if (named === "RiyaASC__NoRelevantLog") {
      console.log("Rejected with RiyaASC__NoRelevantLog.");
      console.log("The proof verified. The receipt succeeded. The emitter was not the real");
      console.log("adapter, so `_dispatch` skipped every log and `submit` reverted.");
      console.log("\nThe emitter pin held. No forged value can enter riya.\n");
      return;
    }
    if (named !== null) {
      console.log(`Rejected with ${named}. Still a rejection — no forged value applied.`);
      return;
    }
    // A revert we could not decode is still a revert: the state did not move.
    console.log("Rejected (undecoded revert). No forged value applied.");
    console.log(error instanceof Error ? `  ${error.message.split("\n")[0]}` : String(error));
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
