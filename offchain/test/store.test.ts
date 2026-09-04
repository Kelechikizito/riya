// Unit tests for the crash-recovery store.
//
// The ordering test is the important one. It guards the rule from step 5, and the store's
// `ORDER BY` is the only place in the whole repo where that rule is enforced.

import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { WorkerStore } from "../src/store.js";

function freshStore(): WorkerStore {
  return new WorkerStore(join(mkdtempSync(join(tmpdir(), "riya-")), "test.db"));
}

const detected = (blockNumber: number, txIndex: number, logIndex = 0) => ({
  txHash: `0x${blockNumber.toString(16).padStart(4, "0")}${txIndex}`,
  logIndex,
  blockNumber,
  txIndex,
  source: "escrow" as const,
});

/*//////////////////////////////////////////////////////////////
                             ORDERING
//////////////////////////////////////////////////////////////*/

// Events at (100, 2), (100, 5) and (101, 0) arriving out of order must come back in that
// sequence. Getting this wrong either shortchanges a depositor of yield they earned or
// pays them out of everyone else's, and neither one throws or writes an unusual log.
test("pending() returns events in Ethereum's order regardless of arrival order", () => {
  const store = freshStore();

  store.insertDetected(detected(101, 0));
  store.insertDetected(detected(100, 5));
  store.insertDetected(detected(100, 2));

  const order = store.pending().map((r) => [r.blockNumber, r.txIndex]);
  assert.deepEqual(order, [
    [100, 2],
    [100, 5],
    [101, 0],
  ]);

  store.close();
});

test("two logs in one transaction stay ordered by logIndex", () => {
  const store = freshStore();

  store.insertDetected({ ...detected(100, 3), logIndex: 4 });
  store.insertDetected({ ...detected(100, 3), logIndex: 1 });

  assert.deepEqual(
    store.pending().map((r) => r.logIndex),
    [1, 4],
  );

  store.close();
});

test("a retried event still sorts ahead of its successor", () => {
  // The retry of event n has to hold up event n + 1 rather than let it overtake. The queue
  // enforces that by stopping the drain, and the store has to keep n at the front for it.
  const store = freshStore();

  store.insertDetected(detected(100, 0));
  store.insertDetected(detected(101, 0));
  store.recordAttempt(detected(100, 0).txHash, 0, "proof builder down");

  assert.equal(store.pending()[0]!.blockNumber, 100);
  assert.equal(store.pending()[0]!.attempts, 1);

  store.close();
});

/*//////////////////////////////////////////////////////////////
                          CRASH RECOVERY
//////////////////////////////////////////////////////////////*/

test("an event left as submitted is still pending after a restart", () => {
  // The awkward case the store exists for: proved and submitted, but the outcome never
  // seen. `isConsumed` covers finished work; only the store knows about this one.
  const path = join(mkdtempSync(join(tmpdir(), "riya-")), "restart.db");

  const first = new WorkerStore(path);
  first.insertDetected(detected(100, 0));
  first.setStatus(detected(100, 0).txHash, 0, "submitted", { replayKey: "0xabc" });
  first.close();

  const second = new WorkerStore(path);
  const pending = second.pending();
  assert.equal(pending.length, 1);
  assert.equal(pending[0]!.status, "submitted");
  assert.equal(pending[0]!.replayKey, "0xabc");
  second.close();
});

test("rescanning does not reset an event that is already in flight", () => {
  // The restart rescan deliberately overlaps, so it re-finds events it has already seen.
  // Resetting one of those to `detected` would cause a second submit.
  const store = freshStore();

  store.insertDetected(detected(100, 0));
  store.setStatus(detected(100, 0).txHash, 0, "submitted");

  const isNew = store.insertDetected(detected(100, 0));
  assert.equal(isNew, false);
  assert.equal(store.pending()[0]!.status, "submitted");

  store.close();
});

test("confirmed and dead events drop out of the queue", () => {
  const store = freshStore();

  store.insertDetected(detected(100, 0));
  store.insertDetected(detected(101, 0));
  store.insertDetected(detected(102, 0));
  store.setStatus(detected(100, 0).txHash, 0, "confirmed");
  store.setStatus(detected(101, 0).txHash, 0, "dead", { lastError: "NoRelevantLog" });

  assert.deepEqual(
    store.pending().map((r) => r.blockNumber),
    [102],
  );
  assert.deepEqual(
    store.deadLettered().map((r) => r.lastError),
    ["NoRelevantLog"],
  );

  store.close();
});

/*//////////////////////////////////////////////////////////////
                          RESUME POINT
//////////////////////////////////////////////////////////////*/

test("resumeFromBlock anchors on the earliest unfinished block, not the newest seen", () => {
  // A confirmed event at 200 means nothing if 150 is still pending; resuming from 201
  // would lose it entirely.
  const store = freshStore();

  store.insertDetected(detected(150, 0));
  store.insertDetected(detected(200, 0));
  store.setStatus(detected(200, 0).txHash, 0, "confirmed");

  assert.equal(store.resumeFromBlock(0, 20), 130);

  store.close();
});

test("resumeFromBlock falls back to the configured start on a cold store", () => {
  assert.equal(freshStore().resumeFromBlock(8_000_000, 200), 8_000_000);
});

test("resumeFromBlock never rewinds past the configured start", () => {
  const store = freshStore();
  store.insertDetected(detected(100, 0));
  assert.equal(store.resumeFromBlock(90, 200), 90);
  store.close();
});
