"use client";

import { useMemo, useState } from "react";
import { ConnectButton } from "@/components/site/ConnectButton";
import { parseUnits } from "viem";
import { useWriteContract } from "wagmi";
import { ADDRESSES, ASSUMED_YIELD_RATE_BPS, loanLedgerAbi } from "@/lib/contracts";
import {
  ASSET_DECIMALS,
  formatDuration,
  formatPercent,
  formatUsd,
  yearsToZero,
} from "@/lib/format";
import { SCORE_TIERS, tierForScore } from "@/lib/score";
import { effectiveDebt, usePosition } from "@/lib/usePosition";
import { useActivity, type ActivityEvent } from "@/lib/useActivity";
import { useDeposit } from "@/lib/useDeposit";

export function Dashboard() {
  const { position, live, connected } = usePosition();

  const tier = tierForScore(Number(position.score));
  const borrowCeiling =
    (position.collateral * position.maxLtvBps) / 10_000n;
  const available =
    borrowCeiling > position.debt ? borrowCeiling - position.debt : 0n;

  // Settlement is lazy, so the stored debt is stale by whatever yield has been proven
  // since the position was last touched. Showing the settled figure is what makes a
  // harvest visible the moment its proof lands, rather than on the user's next action.
  const owed = effectiveDebt(position);

  const totalDrawn = position.debt + position.repaidByYield;
  const retiredPct =
    totalDrawn > 0n ? Number((position.repaidByYield * 100n) / totalDrawn) : 0;

  const years = yearsToZero(position.selfRepayRateBps);

  return (
    <div className="mx-auto max-w-6xl px-5 py-12 sm:px-8 sm:py-16">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Dashboard</p>
          <h1 className="mt-3 text-[2rem] font-semibold leading-tight sm:text-[2.5rem]">
            Your position
          </h1>
        </div>
        <ConnectButton />
      </div>

      {!live && <DataBanner connected={connected} />}

      {/* ------------------------------------------------------------ top row */}
      <div className="mt-8 grid gap-4 lg:grid-cols-[1.15fr_1fr]">
        {/* Debt — the number the product is about */}
        <div className="card p-6 sm:p-8">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="eyebrow">Outstanding debt</p>
              <p className="mt-3 font-mono text-[2.75rem] leading-none tabular text-credit-400 sm:text-[3.5rem]">
                {formatUsd(owed)}
              </p>
              {position.pendingYield > 0n && (
                <p className="mt-2 font-mono text-[12px] text-yield-300">
                  {formatUsd(position.pendingYield)} proven, applied on your next
                  action
                </p>
              )}
            </div>
            <span className="rounded-full border border-credit-400/25 px-3 py-1 text-[11px] uppercase tracking-[0.14em] text-credit-400">
              Creditcoin
            </span>
          </div>

          {years !== null ? (
            <p className="mt-5 text-[15px] leading-relaxed text-muted">
              Gone in{" "}
              <span className="text-ink">{formatDuration(years)}</span> at{" "}
              {formatPercent(ASSUMED_YIELD_RATE_BPS, 1)} yield — without you
              paying anything.
            </p>
          ) : (
            <p className="mt-5 text-[15px] leading-relaxed text-muted">
              Nothing owed. Redraw at your current limit whenever you like.
            </p>
          )}

          <div className="mt-7">
            <div className="flex items-center justify-between text-[11px] uppercase tracking-[0.14em] text-faint">
              <span>Retired by yield</span>
              <span className="font-mono text-yield-300">{retiredPct}%</span>
            </div>
            <div className="mt-2.5 h-2 w-full overflow-hidden rounded-full bg-line">
              <div
                className="h-full rounded-full bg-yield-300 transition-[width] duration-700 ease-[cubic-bezier(0.16,1,0.3,1)]"
                style={{ width: `${retiredPct}%` }}
              />
            </div>
            <p className="mt-2.5 font-mono text-[12px] text-faint">
              {formatUsd(position.repaidByYield)} of{" "}
              {formatUsd(totalDrawn)} drawn
            </p>
          </div>
        </div>

        {/* Collateral + balances */}
        <div className="grid gap-4">
          <Tile
            label="Collateral on Ethereum"
            value={formatUsd(position.collateral)}
            tone="yield"
            note="Supplied to Aave V4 · locked in v1"
            chip="Ethereum"
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <Tile
              label="rUSD balance"
              value={formatUsd(position.rUsdBalance)}
              tone="ink"
              note="Spendable on Creditcoin"
            />
            <Tile
              label="Still available"
              value={formatUsd(available)}
              tone="ink"
              note={`At your ${formatPercent(position.maxLtvBps)} limit`}
            />
          </div>
        </div>
      </div>

      {/* --------------------------------------------------------- second row */}
      <div className="mt-4 grid gap-4 lg:grid-cols-[1fr_1fr_1.1fr]">
        <ScoreCard score={Number(position.score)} tierLabel={tier.label} />
        <BorrowPanel available={available} live={live} />
        <ActivityFeed />
      </div>

      {/* ---------------------------------------------------------- third row */}
      <div className="mt-4">
        <DepositPanel />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ pieces */

function DataBanner({ connected }: { connected: boolean }) {
  return (
    <div className="mt-8 flex flex-col gap-2 rounded-xl border border-dashed border-credit-400/30 bg-credit-400/5 p-5 sm:flex-row sm:items-center sm:gap-4">
      <span className="inline-flex w-fit items-center gap-2 rounded-full border border-credit-400/30 px-2.5 py-0.5 text-[10px] uppercase tracking-[0.14em] text-credit-400">
        <span className="h-1 w-1 rounded-full bg-credit-400" />
        Sample data
      </span>
      <p className="text-[14px] leading-relaxed text-muted">
        {connected
          ? "riya's contracts are not deployed to this network yet, so these are illustrative numbers from the walkthrough's worked example."
          : "Connect a wallet to read your live position. Until then these are illustrative numbers from the walkthrough's worked example."}
      </p>
    </div>
  );
}

function Tile({
  label,
  value,
  tone,
  note,
  chip,
}: {
  label: string;
  value: string;
  tone: "yield" | "credit" | "ink";
  note?: string;
  chip?: string;
}) {
  const color =
    tone === "yield"
      ? "text-yield-300"
      : tone === "credit"
        ? "text-credit-400"
        : "text-ink";
  return (
    <div className="card p-6">
      <div className="flex items-start justify-between gap-3">
        <p className="eyebrow">{label}</p>
        {chip && (
          <span className="rounded-full border border-yield-300/25 px-2.5 py-0.5 text-[10px] uppercase tracking-[0.14em] text-yield-300">
            {chip}
          </span>
        )}
      </div>
      <p className={`mt-3 font-mono text-2xl tabular sm:text-[1.75rem] ${color}`}>
        {value}
      </p>
      {note && <p className="mt-2 text-[12px] text-faint">{note}</p>}
    </div>
  );
}

function ScoreCard({ score, tierLabel }: { score: number; tierLabel: string }) {
  return (
    <div className="card p-6">
      <p className="eyebrow">Credit score</p>
      <div className="mt-3 flex items-baseline gap-3">
        <span className="font-mono text-[2.5rem] leading-none tabular text-credit-400">
          {score}
        </span>
        <span className="text-sm text-muted">{tierLabel}</span>
      </div>

      <ul className="mt-6 space-y-1.5">
        {SCORE_TIERS.map((t) => {
          const active = score >= t.min && score <= t.max;
          return (
            <li key={t.min} className="flex items-center gap-3">
              <span
                className={`w-14 shrink-0 font-mono text-[11px] tabular ${
                  active ? "text-credit-400" : "text-faint"
                }`}
              >
                {t.min}–{t.max === 100 ? "100" : t.max}
              </span>
              <div className="h-1 flex-1 overflow-hidden rounded-full bg-line">
                <div
                  className={`h-full rounded-full ${
                    active ? "bg-credit-400" : "bg-line-soft"
                  }`}
                  style={{ width: `${(t.ltvBps / 5_000) * 100}%` }}
                />
              </div>
              <span
                className={`w-9 shrink-0 text-right font-mono text-[11px] tabular ${
                  active ? "text-ink" : "text-faint"
                }`}
              >
                {t.ltvBps / 100}%
              </span>
            </li>
          );
        })}
      </ul>

      <p className="mt-5 text-[12px] leading-relaxed text-faint">
        Only yield-retired debt moves this. Repaying in cash does not.
      </p>
    </div>
  );
}

function BorrowPanel({ available, live }: { available: bigint; live: boolean }) {
  const [mode, setMode] = useState<"borrow" | "repay">("borrow");
  const [amount, setAmount] = useState("");
  const { writeContract, isPending, error } = useWriteContract();

  const parsed = useMemo(() => {
    if (!amount) return null;
    try {
      return parseUnits(amount, ASSET_DECIMALS);
    } catch {
      return null;
    }
  }, [amount]);

  const overLimit = mode === "borrow" && parsed !== null && parsed > available;
  const canSubmit =
    live && Boolean(ADDRESSES.loanLedger) && parsed !== null && parsed > 0n && !overLimit;

  function submit() {
    if (!canSubmit || !ADDRESSES.loanLedger || parsed === null) return;
    writeContract({
      address: ADDRESSES.loanLedger,
      abi: loanLedgerAbi,
      functionName: mode,
      args: [parsed],
    });
  }

  return (
    <div className="card flex flex-col p-6">
      <div className="flex gap-1 rounded-full border border-line p-1">
        {(["borrow", "repay"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => setMode(m)}
            aria-pressed={mode === m}
            className={`flex-1 cursor-pointer rounded-full px-4 py-2 text-sm font-medium capitalize transition-colors duration-200 ${
              mode === m ? "bg-yield-300 text-void" : "text-muted hover:text-ink"
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      <label
        htmlFor="amount"
        className="mt-6 block text-[11px] uppercase tracking-[0.14em] text-faint"
      >
        Amount in rUSD
      </label>
      <div className="mt-2 flex items-center gap-2 rounded-xl border border-line bg-raised px-4 py-3 focus-within:border-yield-300/50">
        <input
          id="amount"
          inputMode="decimal"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full bg-transparent font-mono text-lg tabular text-ink outline-none placeholder:text-faint"
        />
        <span className="font-mono text-xs text-faint">rUSD</span>
      </div>

      {mode === "borrow" && (
        <p className="mt-2.5 font-mono text-[12px] text-faint">
          Available: {formatUsd(available)}
        </p>
      )}
      {overLimit && (
        <p className="mt-2.5 text-[12px] text-danger">
          Above your current limit. Let yield retire more debt to raise it.
        </p>
      )}
      {error && (
        <p className="mt-2.5 text-[12px] text-danger">
          {error.message.split("\n")[0]}
        </p>
      )}

      <button
        type="button"
        onClick={submit}
        disabled={!canSubmit || isPending}
        className="mt-auto w-full cursor-pointer rounded-full bg-yield-300 px-5 py-3 pt-3 text-sm font-medium text-void transition-colors duration-200 hover:bg-yield-200 disabled:cursor-not-allowed disabled:bg-line disabled:text-faint"
      >
        {isPending
          ? "Confirm in wallet…"
          : live
            ? `${mode === "borrow" ? "Borrow" : "Repay"} rUSD`
            : "Awaiting deployment"}
      </button>

      {!live && (
        <p className="mt-3 text-center text-[11px] leading-relaxed text-faint">
          Enabled once LoanLedger is deployed and its address is set.
        </p>
      )}
    </div>
  );
}

/**
 * The Ethereum half, which is the only place a position can start.
 *
 * The panel is deliberately explicit that the deposit does not land on Creditcoin by
 * itself. A user who deposits and sees nothing appear would assume it failed; the honest
 * answer is that Creditcoin has to attest the block first, and that wait is the product.
 */
function DepositPanel() {
  const { step, error, txHash, balance, minDeposit, available, deposit, reset } =
    useDeposit();
  const [amount, setAmount] = useState("");

  const parsed = useMemo(() => {
    if (!amount) return null;
    try {
      return parseUnits(amount, ASSET_DECIMALS);
    } catch {
      return null;
    }
  }, [amount]);

  const belowFloor = parsed !== null && parsed < minDeposit;
  const busy =
    step === "switching" ||
    step === "minting" ||
    step === "approving" ||
    step === "depositing";
  const canSubmit = available && parsed !== null && parsed > 0n && !belowFloor && !busy;

  return (
    <div className="card p-6 sm:p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="eyebrow">Add collateral</p>
          <h2 className="mt-2 text-[1.35rem] font-semibold">Deposit on Ethereum</h2>
          <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-muted">
            Your dollars stay on Ethereum earning Aave yield. Only a proof crosses to
            Creditcoin, and that is what becomes your collateral.
          </p>
        </div>
        <span className="rounded-full border border-yield-300/25 px-3 py-1 text-[11px] uppercase tracking-[0.14em] text-yield-300">
          Sepolia
        </span>
      </div>

      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-end">
        <div className="flex-1">
          <label
            htmlFor="deposit-amount"
            className="block text-[11px] uppercase tracking-[0.14em] text-faint"
          >
            Amount
          </label>
          <div className="mt-2 flex items-center gap-2 rounded-xl border border-line bg-raised px-4 py-3 focus-within:border-yield-300/50">
            <input
              id="deposit-amount"
              inputMode="decimal"
              placeholder="1000.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full bg-transparent font-mono text-lg tabular text-ink outline-none placeholder:text-faint"
            />
            <span className="font-mono text-xs text-faint">mUSD</span>
          </div>
        </div>

        <button
          type="button"
          onClick={() => parsed && deposit(parsed)}
          disabled={!canSubmit}
          className="cursor-pointer rounded-full bg-yield-300 px-6 py-3 text-sm font-medium text-void transition-colors duration-200 hover:bg-yield-200 disabled:cursor-not-allowed disabled:bg-line disabled:text-faint sm:w-auto"
        >
          {stepLabel(step, available)}
        </button>
      </div>

      <div className="mt-3 flex flex-wrap gap-x-6 gap-y-1 font-mono text-[12px] text-faint">
        <span>Balance: {formatUsd(balance)}</span>
        <span>Minimum: {formatUsd(minDeposit)}</span>
      </div>

      {belowFloor && (
        <p className="mt-2.5 text-[12px] text-danger">
          Below the {formatUsd(minDeposit)} floor. Every deposit costs the same to prove,
          whatever its size.
        </p>
      )}
      {error && <p className="mt-2.5 text-[12px] text-danger">{error}</p>}

      {step === "proving" && (
        <div className="mt-5 rounded-xl border border-dashed border-yield-300/30 bg-yield-300/5 p-4">
          <p className="text-[14px] text-ink">
            Deposited on Ethereum. Waiting for Creditcoin to attest the block.
          </p>
          <p className="mt-1.5 text-[13px] leading-relaxed text-muted">
            The readability worker proves the transaction through the Block Prover
            Precompile once the block is attested. Your collateral appears above when it
            does. Nothing here is bridged, and no tokens move between chains.
          </p>
          {txHash && (
            <a
              href={`https://sepolia.etherscan.io/tx/${txHash}`}
              target="_blank"
              rel="noreferrer"
              className="mt-2.5 inline-block font-mono text-[12px] text-yield-300 underline underline-offset-2"
            >
              View on Etherscan
            </a>
          )}
          <button
            type="button"
            onClick={reset}
            className="mt-3 block cursor-pointer text-[12px] text-faint underline underline-offset-2 hover:text-muted"
          >
            Deposit again
          </button>
        </div>
      )}

      {!available && (
        <p className="mt-4 text-[12px] leading-relaxed text-faint">
          Enabled once RiyaEscrow and the demo dollar are deployed and their addresses are
          set.
        </p>
      )}
    </div>
  );
}

function stepLabel(step: string, available: boolean): string {
  if (!available) return "Awaiting deployment";
  switch (step) {
    case "switching":
      return "Switch network…";
    case "minting":
      return "Minting…";
    case "approving":
      return "Approving…";
    case "depositing":
      return "Confirm deposit…";
    case "proving":
      return "Awaiting proof";
    default:
      return "Deposit";
  }
}

function ActivityFeed() {
  const { events, live } = useActivity();

  return (
    <div className="card flex flex-col p-6">
      <div className="flex items-center justify-between">
        <p className="eyebrow">Proven activity</p>
        {!live && (
          <span className="text-[10px] uppercase tracking-[0.14em] text-faint">
            Sample
          </span>
        )}
      </div>

      <ul className="mt-5 space-y-4">
        {events.map((event: ActivityEvent) => {
          const isHarvest = event.kind === "harvest";
          const isDeposit = event.kind === "deposit";
          const tone = isHarvest || isDeposit ? "text-yield-300" : "text-credit-400";
          return (
            <li key={event.txHash} className="flex items-start gap-3">
              <span
                className={`mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full ${
                  isHarvest || isDeposit ? "bg-yield-300" : "bg-credit-400"
                }`}
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-3">
                  <p className="text-[13px] text-ink">{event.label}</p>
                  <p className={`font-mono text-[13px] tabular ${tone}`}>
                    {isHarvest ? "−" : "+"}
                    {formatUsd(event.amount)}
                  </p>
                </div>
                <p className="truncate font-mono text-[11px] text-faint">
                  {event.detail}
                </p>
                {event.explorerUrl ? (
                  <a
                    href={event.explorerUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="mt-0.5 inline-block text-[11px] text-faint underline decoration-line underline-offset-2 hover:text-muted"
                  >
                    {event.at}
                  </a>
                ) : (
                  <p className="mt-0.5 text-[11px] text-faint">{event.at}</p>
                )}
              </div>
            </li>
          );
        })}
      </ul>

      <p className="mt-6 text-[11px] leading-relaxed text-faint">
        Every entry corresponds to an Ethereum transaction that Creditcoin
        verified itself. Nothing here is asserted by riya.
      </p>
    </div>
  );
}
