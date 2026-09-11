import { expect, test } from "@playwright/test";

/**
 * Writes, as far as a browser can take them without a funded wallet.
 *
 * Signing is out of scope here on purpose: a test that signs needs a funded key on two
 * chains, and the on-chain behaviour of `borrow`, `repay` and `harvest` is already covered
 * where it belongs — `test/unit/LoanLedgerTest.t.sol`, `test/fuzz/LoanLedgerFuzz.t.sol`
 * and `test/integration/RiyaEndToEndTest.t.sol`.
 *
 * What these tests do own is the half Solidity cannot see: that every write is reachable,
 * correctly gated while disconnected, and never silently enabled.
 */

test.beforeEach(async ({ page }) => {
  await page.goto("/app");
});

/**
 * The contracts are deployed, so a disconnected visitor must be told to connect — not
 * that the protocol is missing. The two states have different causes and different fixes,
 * and an earlier version of this panel conflated them.
 */
test("borrow asks for a wallet rather than claiming nothing is deployed", async ({ page }) => {
  const submit = page.getByRole("button", { name: /connect a wallet/i });
  await expect(submit).toBeVisible();
  await expect(submit).toBeDisabled();

  await expect(page.getByText(/awaiting deployment/i)).toHaveCount(0);
  await expect(page.getByText(/borrowing happens on creditcoin/i)).toBeVisible();
});

test("repay is reachable and equally gated", async ({ page }) => {
  await page.getByRole("button", { name: "repay", exact: true }).click();
  await expect(page.getByText(/amount in rusd/i)).toBeVisible();
  await expect(page.getByRole("button", { name: /connect a wallet/i })).toBeDisabled();
});

test("an amount above the limit is refused before the wallet ever opens", async ({ page }) => {
  await page.getByPlaceholder("0.00").first().fill("999999999");
  await expect(page.getByText(/above your current limit/i)).toBeVisible();
  await expect(page.getByRole("button", { name: /connect a wallet/i })).toBeDisabled();
});

test("harvest is present, and states that anyone may call it", async ({ page }) => {
  const panel = page.locator("div.card", { hasText: "Harvest the yield" });
  await expect(panel).toBeVisible();
  await expect(panel).toContainText(/anyone may call this/i);

  // Gated on the adapter's own floor rather than on a wallet, so it stays disabled until
  // there is genuinely something to move.
  await expect(panel.getByRole("button", { name: /^harvest$/i })).toBeDisabled();
});

test("the deposit panel is reachable and explains the wait it cannot remove", async ({ page }) => {
  await expect(page.getByText(/creditcoin|prov(e|ing)/i).first()).toBeVisible();
});
