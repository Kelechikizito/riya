import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end against a real build, reading the real deployment.
 *
 * `next build` then `next start`, not `next dev`: the generated addresses in
 * `lib/contracts/addresses.ts` are inlined at build time alongside the `NEXT_PUBLIC_*`
 * overrides, so a dev-server run would not exercise the same resolution the demo uses.
 *
 * These tests talk to Sepolia and Creditcoin Testnet over the public RPCs. That is the
 * point — they fail when the deployment is wrong, not only when the code is.
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "line" : [["list"]],
  timeout: 60_000,
  expect: { timeout: 20_000 },
  use: {
    baseURL: "http://127.0.0.1:3100",
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run build && npm run start -- --port 3100",
    url: "http://127.0.0.1:3100",
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
});
