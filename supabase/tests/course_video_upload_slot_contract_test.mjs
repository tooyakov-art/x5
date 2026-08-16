import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationURL = new URL(
  "../migrations/20260726233000_course_video_upload_slots.sql",
  import.meta.url,
);

test("dormant course video slots remain quarantined from API roles", async () => {
  let sql = "";
  try {
    sql = await readFile(migrationURL, "utf8");
  } catch {
    // Keep this as an assertion failure while the RED implementation is absent.
  }

  assert.ok(sql, "course video upload slot migration must exist");
  assert.match(
    sql,
    /create table(?: if not exists)? public\.course_video_upload_slots/i,
  );
  assert.match(sql, /unique\s*\(\s*user_id\s*,\s*upload_key\s*\)/i);
  assert.match(sql, /auth\.uid\(\)/i);
  assert.doesNotMatch(
    sql,
    /v_user_id::text\s*\|\|/i,
    "rate-limit serialization must lock per owner, not per upload key",
  );
  assert.match(sql, /public\.is_x5_developer\(\)/i);
  assert.match(sql, /course_submission/i);
  assert.match(sql, /lesson_video/i);
  assert.match(sql, /rate_limited/i);
  assert.match(sql, /idempotency_conflict/i);
  assert.match(sql, /lease_expires_at/i);
  assert.match(sql, /'reclaimed',\s*true/i);
  assert.match(sql, /'reclaimed',\s*false/i);
  assert.match(sql, /bunny_video_id/i);
  assert.match(sql, /revoke all on table public\.course_video_upload_slots/i);
  assert.match(
    sql,
    /revoke execute on function public\.claim_course_video_upload_slot[\s\S]*?from anon, authenticated/i,
  );
  assert.match(
    sql,
    /revoke execute on function public\.complete_course_video_upload_slot[\s\S]*?from anon, authenticated/i,
  );
  assert.doesNotMatch(
    sql,
    /grant execute on function public\.(?:claim|complete)_course_video_upload_slot[\s\S]*?to authenticated/i,
    "authenticated users must never receive direct EXECUTE on signing-ledger RPCs",
  );
});
