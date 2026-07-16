function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertMatch(actual: string, expected: RegExp, message: string): void {
  assert(expected.test(actual), message);
}

async function refundMigrationSource(): Promise<string> {
  const migrationsUrl = new URL("../../migrations/", import.meta.url);
  const matches: string[] = [];
  for await (const entry of Deno.readDir(migrationsUrl)) {
    if (
      entry.isFile &&
      entry.name.endsWith("_app_store_consumable_refunds.sql")
    ) {
      matches.push(entry.name);
    }
  }
  assert(
    matches.length === 1,
    `expected one consumable refund migration, found ${matches.length}`,
  );
  return await Deno.readTextFile(new URL(matches[0], migrationsUrl));
}

async function rollbackTestSource(): Promise<string> {
  return await Deno.readTextFile(
    new URL(
      "../../tests/20260716_app_store_consumable_refunds_test.sql",
      import.meta.url,
    ),
  );
}

Deno.test("consumable refund RPC is source-bound, debt-safe, and exact once", async () => {
  const source = await refundMigrationSource();

  assertMatch(
    source,
    /create table public\.app_store_consumable_refunds/i,
    "missing append-only consumable refund ledger",
  );
  assertMatch(
    source,
    /primary key\s*\(environment,\s*transaction_id\)/i,
    "refund identity must include App Store environment",
  );
  assertMatch(
    source,
    /create (?:or replace )?function public\.apply_verified_app_store_consumable_refund/i,
    "missing service-only consumable refund RPC",
  );
  assertMatch(
    source,
    /security definer/i,
    "refund RPC must be security definer",
  );
  assertMatch(
    source,
    /set search_path\s*=\s*''/i,
    "refund RPC must pin an empty search_path",
  );
  assertMatch(
    source,
    /from public\.app_store_consumable_transactions/i,
    "Production refunds must bind to the immutable Production purchase row",
  );
  assertMatch(
    source,
    /from public\.app_store_sandbox_review_transactions/i,
    "Sandbox refunds must bind to the isolated Sandbox purchase row",
  );
  for (
    const predicate of [
      /source\.user_id\s*<>\s*p_user_id/i,
      /source\.original_transaction_id\s*<>\s*v_original_transaction_id/i,
      /source\.product_id\s*<>\s*v_product_id/i,
      /source\.environment\s*<>\s*v_environment/i,
      /source\.app_account_token\s*<>\s*p_app_account_token/i,
      /source\.purchase_date\s*<>\s*p_purchase_date/i,
      /source\.quantity\s*<>\s*p_quantity/i,
    ]
  ) {
    assertMatch(
      source,
      predicate,
      `missing strict source predicate ${predicate}`,
    );
  }
  assertMatch(
    source,
    /v_credits_reversed\s*:=\s*source\.credits_granted/i,
    "deduction must come only from the recorded grant",
  );
  assertMatch(
    source,
    /set credits\s*=\s*coalesce\(credits,\s*0\)\s*-\s*v_credits_reversed/i,
    "refund must subtract the recorded grant and permit debt",
  );
  assert(
    !/set credits\s*=\s*greatest\s*\(/i.test(source),
    "refund balance must not be clamped to zero",
  );
  assertMatch(
    source,
    /'status',\s*'already_applied'[\s\S]+?'credits_granted',\s*0/i,
    "re-signed replay must be exact once and never grant credits",
  );
  assert(
    !/existing\.signed_date\s*(?:<>|is distinct from)\s*p_signed_date/i.test(
      source,
    ),
    "a valid re-signed refund must not conflict only on signed_date",
  );
});

Deno.test("consumable refund ledger is immutable to every API role", async () => {
  const source = await refundMigrationSource();
  assertMatch(
    source,
    /alter table public\.app_store_consumable_refunds owner to postgres/i,
    "postgres must own the refund ledger",
  );
  assertMatch(
    source,
    /alter table public\.app_store_consumable_refunds force row level security/i,
    "refund ledger must force RLS",
  );
  assertMatch(
    source,
    /revoke all privileges on table public\.app_store_consumable_refunds\s+from public, anon, authenticated/i,
    "client roles must have no refund ledger privileges",
  );
  assertMatch(
    source,
    /revoke all privileges on table public\.app_store_consumable_refunds\s+from service_role/i,
    "service_role must not mutate the refund ledger directly",
  );
  assertMatch(
    source,
    /grant execute on function public\.apply_verified_app_store_consumable_refund[\s\S]+?to service_role/i,
    "service_role needs only the narrow refund RPC",
  );
});

Deno.test("rollback SQL probes Production, Sandbox, replay, debt, and identity conflicts", async () => {
  const source = await rollbackTestSource();
  for (
    const marker of [
      "production_consumable_refund_failed",
      "sandbox_consumable_refund_failed",
      "consumable_refund_replay_was_not_exact_once",
      "consumable_refund_did_not_create_debt",
      "consumable_refund_debt_was_reused",
      "consumable_refund_identity_mismatch_was_accepted",
      "consumable_refund_rpc_is_client_callable",
      "consumable_refund_ledger_is_not_private",
    ]
  ) {
    assertMatch(
      source,
      new RegExp(marker, "i"),
      `missing rollback marker ${marker}`,
    );
  }
  assertMatch(
    source,
    /rollback;[\s\S]+app_store_consumable_refunds_validated_with_rollback/i,
    "refund probes must be transactionally rolled back",
  );
});
