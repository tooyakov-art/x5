# X5 iOS secure analytics status

Date: 2026-08-10
Branch: `codex/x5-analytics-secure-dashboard`

## Outcome

- New registration requires name, specialist/entrepreneur role, CIS country, and city.
- A random installation UUID records lifecycle, registration, and purchase events without IDFA.
- StoreKit sends only the transaction ID to the protected Apple verification endpoint; the app no longer grants Pro or credits directly.
- App Store aggregates are written to protected `store_metrics_daily`; the previous checked-in public JSON is removed.

## Verification

- `python -m unittest discover -s scripts/tests -p 'test_*.py'`: 7 passed.
- A real Xcode build and StoreKit sandbox UAT are not available on this Windows machine and remain required before release.

## Blockers and next action

The feature branch must not be released until the shared Supabase migration and Edge Functions are deployed with fresh protected service-role and App Store Server API/Notifications secrets, app Apple ID, and Apple root certificates. Historical plaintext credentials must not be reused.

Best next action: configure those protected secrets, deploy the backend, then run an Xcode/TestFlight purchase, renewal, restore, cancellation, and refund test before merging this branch.
