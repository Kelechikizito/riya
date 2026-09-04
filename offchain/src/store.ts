// Step 7: progress that survives a restart.
//
// The chain is the real source of truth and `isConsumed` already answers for *finished*
// work. What it cannot answer for is work that was **in progress** when the worker died —
// detected, proved, maybe even submitted, with the outcome never seen. Without a local
// record a restarting worker has no idea that event ever existed.
//
// SQLite rather than Postgres, deliberately. Postgres earns its keep when several programs
// write the same data at once, and riya has exactly one writer because step 5 forbids a
// second. This is about surviving a restart, not about load, and a single file that travels
// with the worker is one less container between a judge and a running demo.

import { DatabaseSync } from "node:sqlite";

/**
 * Where an event has got to. The order matters: recovery resumes from the stage reached,
 * and `confirmed` is the only terminal success.
 */
export type EventStatus =
  | "detected"
  | "attested"
  | "proved"
  | "submitted"
  | "confirmed"
  | "dead";

export interface EventRecord {
  txHash: string;
  logIndex: number;
  blockNumber: number;
  txIndex: number;
  source: "escrow" | "adapter";
  status: EventStatus;
  replayKey: string | null;
  creditcoinTxHash: string | null;
  attempts: number;
  lastError: string | null;
  updatedAt: number;
}

interface Row {
  tx_hash: string;
  log_index: number;
  block_number: number;
  tx_index: number;
  source: string;
  status: string;
  replay_key: string | null;
  creditcoin_tx_hash: string | null;
  attempts: number;
  last_error: string | null;
  updated_at: number;
}

function toRecord(row: Row): EventRecord {
  return {
    txHash: row.tx_hash,
    logIndex: row.log_index,
    blockNumber: row.block_number,
    txIndex: row.tx_index,
    source: row.source as EventRecord["source"],
    status: row.status as EventStatus,
    replayKey: row.replay_key,
    creditcoinTxHash: row.creditcoin_tx_hash,
    attempts: row.attempts,
    lastError: row.last_error,
    updatedAt: row.updated_at,
  };
}

export class WorkerStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    // WAL keeps a reader (a debugging `sqlite3` session, say) from blocking the worker.
    this.db.exec("PRAGMA journal_mode = WAL");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS events (
        tx_hash            TEXT    NOT NULL,
        log_index          INTEGER NOT NULL,
        block_number       INTEGER NOT NULL,
        tx_index           INTEGER NOT NULL,
        source             TEXT    NOT NULL,
        status             TEXT    NOT NULL,
        replay_key         TEXT,
        creditcoin_tx_hash TEXT,
        attempts           INTEGER NOT NULL DEFAULT 0,
        last_error         TEXT,
        updated_at         INTEGER NOT NULL,
        PRIMARY KEY (tx_hash, log_index)
      );
      CREATE INDEX IF NOT EXISTS events_status_order
        ON events (status, block_number, tx_index, log_index);
    `);
  }

  /**
   * Records a newly seen event, keyed by `(txHash, logIndex)`.
   *
   * `ON CONFLICT DO NOTHING` is what makes the restart rescan safe: re-finding an event
   * that is already `submitted` must not reset it to `detected` and cause a second submit.
   */
  insertDetected(
    event: Omit<EventRecord, "status" | "replayKey" | "creditcoinTxHash" | "attempts" | "lastError" | "updatedAt">,
  ): boolean {
    const result = this.db
      .prepare(
        `INSERT INTO events
           (tx_hash, log_index, block_number, tx_index, source, status, updated_at)
         VALUES (?, ?, ?, ?, ?, 'detected', ?)
         ON CONFLICT (tx_hash, log_index) DO NOTHING`,
      )
      .run(
        event.txHash,
        event.logIndex,
        event.blockNumber,
        event.txIndex,
        event.source,
        Date.now(),
      );
    return result.changes > 0;
  }

  /** Advances one event, optionally attaching the replay key or the Creditcoin tx hash. */
  setStatus(
    txHash: string,
    logIndex: number,
    status: EventStatus,
    extra: { replayKey?: string; creditcoinTxHash?: string; lastError?: string | null } = {},
  ): void {
    this.db
      .prepare(
        `UPDATE events SET
           status             = ?,
           replay_key         = COALESCE(?, replay_key),
           creditcoin_tx_hash = COALESCE(?, creditcoin_tx_hash),
           last_error         = ?,
           updated_at         = ?
         WHERE tx_hash = ? AND log_index = ?`,
      )
      .run(
        status,
        extra.replayKey ?? null,
        extra.creditcoinTxHash ?? null,
        extra.lastError ?? null,
        Date.now(),
        txHash,
        logIndex,
      );
  }

  recordAttempt(txHash: string, logIndex: number, error: string): void {
    this.db
      .prepare(
        `UPDATE events SET attempts = attempts + 1, last_error = ?, updated_at = ?
         WHERE tx_hash = ? AND log_index = ?`,
      )
      .run(error, Date.now(), txHash, logIndex);
  }

  /**
   * Everything still owed work, in the order it happened on Ethereum.
   *
   * **This ordering is the step 5 rule made concrete.** `LoanLedger._settle` stamps
   * `s_yieldPerShare` against a user when their collateral changes, so whether a depositor
   * shares in a harvest depends on the order `RiyaASC` saw the two proofs. Sorting by
   * `(block_number, tx_index, log_index)` is what makes that order match Ethereum's.
   */
  pending(): EventRecord[] {
    const rows = this.db
      .prepare(
        `SELECT * FROM events
         WHERE status NOT IN ('confirmed', 'dead')
         ORDER BY block_number ASC, tx_index ASC, log_index ASC`,
      )
      .all() as unknown as Row[];
    return rows.map(toRecord);
  }

  /** Dead-lettered events, for the alert and for a human to look at. */
  deadLettered(): EventRecord[] {
    const rows = this.db
      .prepare(`SELECT * FROM events WHERE status = 'dead' ORDER BY block_number ASC`)
      .all() as unknown as Row[];
    return rows.map(toRecord);
  }

  /**
   * Where to resume scanning Ethereum.
   *
   * Deliberately the lowest block that is *not* finished rather than the highest block seen:
   * a confirmed event at block 200 means nothing if an event at 150 is still pending, and
   * resuming from 201 would lose it.
   */
  resumeFromBlock(fallback: number, overlap: number): number {
    const row = this.db
      .prepare(
        `SELECT MIN(block_number) AS earliest FROM events
         WHERE status NOT IN ('confirmed', 'dead')`,
      )
      .get() as unknown as { earliest: number | null } | undefined;

    const highest = this.db
      .prepare(`SELECT MAX(block_number) AS latest FROM events`)
      .get() as unknown as { latest: number | null } | undefined;

    const anchor = row?.earliest ?? highest?.latest;
    if (anchor === null || anchor === undefined) return fallback;
    return Math.max(fallback, anchor - overlap);
  }

  close(): void {
    this.db.close();
  }
}
