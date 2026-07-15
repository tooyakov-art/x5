from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
IAP_SERVICE = ROOT / "X5" / "Services" / "IAPService.swift"
X5_APP = ROOT / "X5" / "X5App.swift"
PAYWALL = ROOT / "X5" / "Views" / "PaywallView.swift"
PROFILE = ROOT / "X5" / "Services" / "UserProfile.swift"
LOCALIZATION = ROOT / "X5" / "Services" / "LocalizationService.swift"


class IOSPurchaseLifecycleSourceTests(unittest.TestCase):
    def test_all_storekit_delivery_paths_use_the_mockable_lifecycle(self):
        source = IAP_SERVICE.read_text(encoding="utf-8")

        self.assertIn("final class IAPTransactionLifecycleCoordinator", source)
        self.assertIn("private let transactionLifecycle", source)
        self.assertGreaterEqual(source.count("deliverVerifiedTransaction("), 5)
        self.assertEqual(source.count("await transaction.finish()"), 1)
        self.assertIn("if disposition == .applied", source)

    def test_transaction_completion_cache_is_scoped_to_authenticated_account(self):
        source = IAP_SERVICE.read_text(encoding="utf-8")

        self.assertIn("struct IAPTransactionDeliveryKey: Hashable", source)
        self.assertIn("authenticatedUserID: String?", source)
        self.assertIn("authenticatedUserID: auth.userId", source)

    def test_transaction_completion_cache_distinguishes_later_revocation(self):
        source = IAP_SERVICE.read_text(encoding="utf-8")

        self.assertIn("let revocationDate: Date?", source)
        self.assertIn("revocationDate: transaction.revocationDate", source)

    def test_verified_purchase_records_and_syncs_active_entitlements(self):
        source = IAP_SERVICE.read_text(encoding="utf-8")

        self.assertIn("recordingActivePurchase", source)
        self.assertIn('await syncCurrentEntitlements(source: "purchase")', source)

    def test_verified_revocation_is_retryable_and_refreshes_server_profile(self):
        service = IAP_SERVICE.read_text(encoding="utf-8")
        app = X5_APP.read_text(encoding="utf-8")

        self.assertIn("hasRevocation: transaction.revocationDate != nil", service)
        self.assertIn("transaction.revocationDate != nil", service)
        self.assertIn("Transaction.all", service)
        self.assertIn("maximumTransactions", service)
        self.assertIn("syncRevokedVerifiedTransactions", service)
        self.assertIn(".x5DidChangeVerifiedEntitlement", service)
        self.assertIn(".x5DidChangeVerifiedEntitlement", app)
        self.assertIn("iap.syncRevokedVerifiedTransactions", app)
        self.assertIn("syncStoreKitAndProfile", app)

    def test_failed_profile_reload_has_truthful_confirmation_copy(self):
        paywall = PAYWALL.read_text(encoding="utf-8")
        profile = PROFILE.read_text(encoding="utf-8")
        localization = LOCALIZATION.read_text(encoding="utf-8")

        self.assertIn("profileReloadSucceeded", paywall)
        self.assertIn("-> Bool", profile)
        self.assertEqual(localization.count('"credit_store_success_refresh_pending"'), 3)


if __name__ == "__main__":
    unittest.main()
