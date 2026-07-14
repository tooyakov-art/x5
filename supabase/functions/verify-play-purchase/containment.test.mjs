import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("./index.ts", import.meta.url),
  "utf8",
);

test("production Google Play credit minting stays fail-closed until an exact-once owner ledger exists", () => {
  assert.match(source, /const PLAY_PURCHASES_ENABLED = false;/);
  const guard = source.indexOf("if (!PLAY_PURCHASES_ENABLED)");
  const googleVerification = source.indexOf("googlePlayAccessToken()");
  const profileMutation = source.indexOf('.from("profiles")');

  assert.ok(guard >= 0, "missing production containment guard");
  assert.ok(
    guard < googleVerification,
    "guard must run before Google purchase verification",
  );
  assert.ok(guard < profileMutation, "guard must run before profile mutation");
});
