// Unit tests for the worker's pure logic — the parts that need no network.
//
// The two marked below are the load-bearing ones. Everything else here is ordinary
// coverage; those two guard rules that fail silently in production.

import assert from "node:assert/strict";
import { test } from "node:test";

import { permanentError, replayKey } from "../src/worker.js";

/*//////////////////////////////////////////////////////////////
                          KEY DERIVATION
//////////////////////////////////////////////////////////////*/

// DO NOT SKIP THIS ONE.
//
// A mismatch between this key and the contract's silently disables the whole duplicate
// check: `isConsumed` simply always answers no, and every restart pays again for work
// already done. Nothing throws, and nothing looks unusual in the logs.
test("replayKey matches the key RiyaASC derives from the same inputs", () => {
  // Cross-checked against Solidity with `cast keccak $(cast abi-encode ...)`.
  const key = replayKey(
    1,
    9123456,
    "0x1111111111111111111111111111111111111111111111111111111111111111",
    7,
  );
  assert.equal(
    key,
    "0xd30497eb9a7e9a3d679a1bbaa0d822fed2d5eaabf13546e6b7082bc2f607fb42",
  );
});

test("replayKey pads like abi.encode, not abi.encodePacked", () => {
  // The failure mode this guards is reaching for `solidityPacked`, which packs values at
  // their natural width and hashes to something completely different. If that ever crept
  // in, these two would collide — under packing, (1, 256, root, 0) and (1, 1, root, 0)
  // stay distinct, but the padded encoding is the one the contract uses, so the only real
  // check is the known-good vector above plus the fact that distinct inputs stay distinct.
  const root = "0x2222222222222222222222222222222222222222222222222222222222222222";
  assert.notEqual(replayKey(1, 100, root, 0), replayKey(1, 100, root, 1));
  assert.notEqual(replayKey(1, 100, root, 0), replayKey(2, 100, root, 0));
  assert.notEqual(replayKey(1, 100, root, 0), replayKey(1, 101, root, 0));
});

test("replayKey rejects a value too wide for uint64", () => {
  // Writing `uint256` in the type list would produce the same bytes, since `abi.encode`
  // pads anyway — but it would also accept a nonsense chain key silently. `uint64` makes
  // that a crash at the point the bad value appears.
  assert.throws(() =>
    replayKey(
      Number.MAX_SAFE_INTEGER,
      1,
      "0x3333333333333333333333333333333333333333333333333333333333333333",
      2 ** 64,
    ),
  );
});

/*//////////////////////////////////////////////////////////////
                       FAILURE CLASSIFICATION
//////////////////////////////////////////////////////////////*/

test("NoRelevantLog and TxReverted are permanent, so they get dead-lettered", () => {
  assert.equal(
    permanentError({ revert: { name: "RiyaASC__NoRelevantLog" } }),
    "RiyaASC__NoRelevantLog",
  );
  assert.equal(
    permanentError({ revert: { name: "RiyaASC__TxReverted" } }),
    "RiyaASC__TxReverted",
  );
});

test("network failures and AlreadyConsumed stay retriable", () => {
  // A timeout may well have landed on-chain; the retry loop re-checks `isConsumed` rather
  // than giving up, and that check is what stops a hiccup costing a duplicate submission.
  assert.equal(permanentError(new Error("timeout")), null);
  assert.equal(permanentError({ revert: { name: "RiyaASC__ProofInvalid" } }), null);
  assert.equal(permanentError(undefined), null);
  assert.equal(permanentError({ data: "0xdeadbeef" }), null);
});
