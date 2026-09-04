// The keeper — Ethereum only, and optional.
//
// The whole job:
//
//   every N minutes:
//       accrued = adapter.yieldAccrued()
//       if accrued >= threshold:
//           adapter.harvest()
//
// `harvest()` is permissionless, so this program is a convenience rather than a
// dependency: anybody can call it, and if the keeper dies the protocol keeps working. What
// it produces is the `TokensHarvested` event the worker later proves, which is the only
// connection between the two files — they share `config.ts` and nothing else.
//
// It never imports the SDK. An `@gluwa/usc-sdk` import appearing in this file is the
// clearest sign the keeper/worker separation has broken down.

import { Contract, JsonRpcProvider, Wallet, formatUnits } from "ethers";

import { AAVE_V4_ADAPTER_ABI } from "./abi.js";
import * as config from "./config.js";

/** USDC. Only used to print numbers a human can read. */
const ASSET_DECIMALS = 6;

export class Keeper {
  private readonly adapter: Contract;
  private readonly signer: Wallet;

  /** One transaction at a time: a second harvest arrives below the floor and fails. */
  private inFlight = false;
  private running = false;

  constructor() {
    // The keeper's own endpoint. It writes to Ethereum, where the worker only reads.
    const provider = new JsonRpcProvider(config.SOURCE_RPC_URLS[0]!);
    this.signer = new Wallet(config.keeperPrivateKey(), provider);
    this.adapter = new Contract(
      config.aaveV4AdapterAddress(),
      AAVE_V4_ADAPTER_ABI,
      this.signer,
    );
  }

  private yieldAccrued(): Promise<bigint> {
    return this.adapter.getFunction("yieldAccrued")() as Promise<bigint>;
  }

  private minHarvest(): Promise<bigint> {
    return this.adapter.getFunction("I_MIN_HARVEST")() as Promise<bigint>;
  }

  /**
   * One cycle: read, decide, and only then spend gas.
   *
   * The tempting wrong version is a plain timer that calls `harvest()` on a schedule.
   * `_harvest()` rejects anything below `I_MIN_HARVEST`, so a timer-only keeper burns gas
   * on a guaranteed revert every time it fires early. `yieldAccrued()` is a free read, so
   * checking first costs nothing and skips every one of those.
   */
  async cycle(): Promise<boolean> {
    if (this.inFlight) {
      console.log("Previous harvest still in flight; skipping this cycle.");
      return false;
    }

    const accrued = await this.yieldAccrued();
    const readable = formatUnits(accrued, ASSET_DECIMALS);

    if (accrued < config.keeper.threshold) {
      console.log(
        `Yield ${readable} below threshold ${formatUnits(config.keeper.threshold, ASSET_DECIMALS)}; nothing to do.`,
      );
      return false;
    }

    this.inFlight = true;
    try {
      console.log(`Harvesting ${readable}…`);
      const tx = await (this.adapter.getFunction("harvest")() as Promise<{
        hash: string;
        wait: () => Promise<{ hash: string; blockNumber: number | null } | null>;
      }>);
      const receipt = await tx.wait();
      console.log(
        `Harvested ${readable} in eth ${receipt?.hash ?? tx.hash} (block ${receipt?.blockNumber}). ` +
          `The worker will prove the TokensHarvested event from here.`,
      );
      return true;
    } finally {
      this.inFlight = false;
    }
  }

  /**
   * Runs forever.
   *
   * Deliberately stateless. `yieldAccrued()` is the only input it needs, and a missed cycle
   * costs nothing because the yield is still sitting there next time — so the keeper needs
   * no database at all, and adding one would be a step backwards.
   */
  async start(): Promise<void> {
    const [threshold, floor] = [config.keeper.threshold, await this.minHarvest()];
    if (threshold < floor) {
      console.warn(
        `Keeper threshold ${formatUnits(threshold, ASSET_DECIMALS)} sits below the contract's ` +
          `floor of ${formatUnits(floor, ASSET_DECIMALS)}, so some cycles will revert. ` +
          `On Mainnet it should sit well above it — a harvest withdraws from Aave and then ` +
          `transfers, which can cost more than the amount it moves.`,
      );
    }

    this.running = true;
    console.log(
      `Keeper started. Reading yieldAccrued() every ${config.keeper.pollIntervalMs / 1000}s.`,
    );

    while (this.running) {
      try {
        await this.cycle();
      } catch (error) {
        // Nothing is lost by failing: the yield stays where it is until the next cycle.
        console.error(
          `Cycle failed: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
      await new Promise((resolve) => setTimeout(resolve, config.keeper.pollIntervalMs));
    }
  }

  stop(): void {
    this.running = false;
  }
}

async function main(): Promise<void> {
  const keeper = new Keeper();

  // The demo moment is "one harvest, one proof, and every borrower's debt drops at once",
  // which wants a button rather than a background process. `--once` is that button.
  if (process.argv.includes("--once")) {
    const harvested = await keeper.cycle();
    process.exit(harvested ? 0 : 1);
  }

  const shutdown = () => {
    console.log("Shutting down after the current cycle.");
    keeper.stop();
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  await keeper.start();
}

if (process.argv[1] !== undefined && import.meta.url.endsWith(process.argv[1].split("/").pop()!)) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
