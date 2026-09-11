import { expect, test } from "@playwright/test";

import { DEPLOYED } from "../lib/contracts/addresses";

/**
 * Reads, end to end, against the real deployment.
 *
 * These are not snapshot tests. They assert that the generated addresses reach the page
 * and that live contract reads resolve — so they fail when `lib/contracts/` has drifted
 * from what is actually deployed, which is the failure a unit test cannot see.
 */

/** Every address the app was generated with must be a real one. */
test("the generated deployment is complete and well formed", async () => {
  for (const key of ["loanLedger", "riyaAsc", "riyaUsd", "escrow", "adapter", "mockUsd"] as const) {
    const address = DEPLOYED[key];
    expect(address, `${key} is missing from lib/contracts/addresses.ts`).toBeDefined();
    expect(address, `${key} is not an address`).toMatch(/^0x[0-9a-fA-F]{40}$/);
  }
});

test("the landing page publishes the deployed addresses it was built with", async ({ page }) => {
  await page.goto("/");

  const deployed = page.locator("#deployed");
  await expect(deployed).toContainText("What is deployed");
  await expect(deployed).toContainText("Creditcoin Testnet");
  await expect(deployed).toContainText("Ethereum Sepolia");

  // Rendered truncated, so match the ends rather than the whole string. If this fails,
  // the page is showing an address the build was not generated from.
  for (const key of ["loanLedger", "riyaAsc", "riyaUsd"] as const) {
    const address = DEPLOYED[key]!;
    await expect(deployed).toContainText(address.slice(0, 6));
    await expect(deployed).toContainText(address.slice(-4));
  }
});

test("the collateral section reads the adapter's live position on Sepolia", async ({ page }) => {
  const failures: string[] = [];
  page.on("console", (m) => {
    if (m.type() === "error") failures.push(m.text());
  });

  await page.goto("/");
  const assets = page.locator("#assets");
  await expect(assets).toContainText("What you can deposit");

  // The four adapter reads land as dollar figures. Until one renders, the read has not
  // resolved — which is exactly the regression worth catching.
  await expect(assets.getByText(/\$[\d,]+/).first()).toBeVisible();

  expect(failures.join("\n")).not.toMatch(/ContractFunctionExecutionError|reverted/i);
});

test("the dashboard reads the ledger without a wallet connected", async ({ page }) => {
  await page.goto("/app");

  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  // Protocol totals need no wallet: they are not per-user.
  await expect(page.getByText(/\$[\d,]+/).first()).toBeVisible();
});
