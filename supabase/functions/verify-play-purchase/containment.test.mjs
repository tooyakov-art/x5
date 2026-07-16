import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(
  new URL("./index.ts", import.meta.url),
  "utf8",
);
const entitlements = readFileSync(
  new URL("./entitlements.mjs", import.meta.url),
  "utf8",
);

test("production Google Play verification mints through the exact-once owner ledger", () => {
  assert.doesNotMatch(
    source,
    /PLAY_PURCHASES_ENABLED\s*=\s*false/,
    "the deployed Google Play verifier must not be replaced by the old disabled stub",
  );

  const googleVerification = Math.min(
    ...[
      source.indexOf("loadGoogleSubscription("),
      source.indexOf("loadGoogleProduct("),
    ].filter((index) => index >= 0),
  );
  const ledgerMutation = source.indexOf(
    '.rpc("apply_android_purchase_entitlement"',
  );

  assert.ok(googleVerification >= 0, "missing Google Play API verification");
  assert.ok(
    ledgerMutation > googleVerification,
    "ledger must run after Google verification",
  );
  assert.doesNotMatch(
    source,
    /\.from\(["\']profiles["\']\)/,
    "the verifier must not mutate profile balances directly",
  );
  assert.match(
    source,
    /const claimKey = `\$\{productId\}:\$\{tokenHash\}:\$\{expiry \|\| "one-time"\}`/,
  );
});

test("deployed package and every current store product stay represented", () => {
  assert.match(
    entitlements,
    /ANDROID_PACKAGE_NAME = "com\.x5marketing\.mobile"/,
  );

  for (
    const productId of [
      "x5_lite_monthly_v2",
      "x5_pro_monthly_v2",
      "x5_max_monthly_v2",
      "x5_verified_monthly_v2",
      "x5_credits_1000_v2",
      "x5_credits_2000_v2",
      "x5_credits_5000_v2",
    ]
  ) {
    assert.match(entitlements, new RegExp(`\\b${productId}\\b`));
  }
});
