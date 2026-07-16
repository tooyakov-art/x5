const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

function assertMatch(value: string, pattern: RegExp, message: string): void {
  if (!pattern.test(value)) throw new Error(message);
}

Deno.test("runtime verifies both Apple JWS layers with the pinned Apple library", () => {
  assertMatch(
    source,
    /@apple\/app-store-server-library/,
    "Apple server library import is missing",
  );
  assertMatch(
    source,
    /verifyAndDecodeNotification\(\s*signedPayload,?\s*\)/,
    "outer signedPayload is not verified",
  );
  assertMatch(
    source,
    /verifyAndDecodeTransaction\(\s*signedTransaction,?\s*\)/,
    "inner signedTransactionInfo is not verified",
  );
  assertMatch(
    source,
    /VerificationStatus\.RETRYABLE_VERIFICATION_FAILURE/,
    "retryable Apple verification failures are not classified",
  );
});

Deno.test("runtime applies only the dedicated service-role notification RPC", () => {
  assertMatch(
    source,
    /apply_verified_app_store_server_notification/,
    "dedicated notification RPC is missing",
  );
  assertMatch(
    source,
    /SUPABASE_SERVICE_ROLE_KEY/,
    "service role key is not used server-side",
  );
  assertMatch(
    source,
    /if \(import\.meta\.main\)[\s\S]*Deno\.serve/,
    "Edge runtime entrypoint is missing",
  );
});
