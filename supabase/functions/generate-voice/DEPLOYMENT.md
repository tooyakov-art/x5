# Voice generation deployment

Do not deploy this feature automatically. Apply the independent
`20260726222900_revoke_account_delete_helper_acl.sql` security hotfix first. The
account-cleanup worker and its Vault secret must then pass the health gate
documented in `../account-deletion-cleanup/DEPLOYMENT.md` before applying the
voice ledger and queued-cleanup migrations. Both migrations must be live before
either voice function receives traffic.

Required server-only environment:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FAL_KEY`

Deploy the authenticated client function normally:

```sh
supabase functions deploy generate-voice
```

The callback function is intentionally configured with `verify_jwt = false` in
`supabase/config.toml`, because fal does not send a Supabase JWT. It rejects all
callbacks unless fal's Ed25519 signature, raw-body hash, signed request ID, and
five-minute timestamp window verify against fal's official JWKS:

```sh
supabase functions deploy voice-generation-webhook --no-verify-jwt
```

Before release, force a submit-response timeout in staging and verify:

1. one credit debit and one fal queue request;
2. the signed callback binds its request ID through the opaque claim URL;
3. a client retry polls/replays and never submits a second job;
4. duplicate callback delivery is idempotent;
5. an unbound ambiguous submission is not automatically refunded;
6. a terminal provider error refunds exactly once;
7. generated audio is copied into private X5 Storage before the fal URL expires.
