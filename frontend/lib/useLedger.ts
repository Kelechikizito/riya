"use client";

import { useCallback } from "react";
import { creditcoinTestnet } from "./chains";
import { ADDRESSES, loanLedgerAbi } from "./contracts";
import { useTx, type TxState } from "./useTx";

export type LedgerActions = {
  tx: TxState;
  /** False when the ledger is not deployed, so the panel can say why it is inert. */
  available: boolean;
  borrow: (amount: bigint) => Promise<void>;
  repay: (amount: bigint) => Promise<void>;
  /**
   * Applies proven yield to debt without repaying anything meaningful.
   *
   * `LoanLedger` settles lazily: a harvest proof updates `s_yieldPerShare`, but a given
   * borrower's `s_debt` only moves the next time they touch the contract. `repay(1)` is
   * the cheapest way to touch it — one unit of rUSD, six decimals, so a ten-thousandth of
   * a cent — and it exists because watching a proof land and the debt not move is the
   * demo's most confusing moment.
   */
  settle: () => Promise<void>;
};

/** Every write `LoanLedger` exposes to a user. Both live on Creditcoin. */
export function useLedgerActions(): LedgerActions {
  const tx = useTx(creditcoinTestnet.id);
  const ledger = ADDRESSES.loanLedger;

  const call = useCallback(
    async (functionName: "borrow" | "repay", amount: bigint) => {
      if (!ledger) return;
      await tx.send({ address: ledger, abi: loanLedgerAbi, functionName, args: [amount] });
    },
    [ledger, tx],
  );

  return {
    tx,
    available: Boolean(ledger),
    borrow: useCallback((amount: bigint) => call("borrow", amount), [call]),
    repay: useCallback((amount: bigint) => call("repay", amount), [call]),
    settle: useCallback(() => call("repay", 1n), [call]),
  };
}
