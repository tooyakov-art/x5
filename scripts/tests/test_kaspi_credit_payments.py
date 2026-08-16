from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260813150000_kaspi_credit_payments.sql"
).read_text(encoding="utf-8")
SERVICE = (ROOT / "X5" / "Services" / "KaspiCreditPaymentService.swift").read_text(
    encoding="utf-8"
)
PAYWALL = (ROOT / "X5" / "Views" / "PaywallView.swift").read_text(
    encoding="utf-8"
)
PROVIDER = (
    ROOT / "supabase" / "functions" / "kaspi-pay-provider" / "index.ts"
).read_text(encoding="utf-8")


class KaspiCreditPaymentsTests(unittest.TestCase):
    def test_exact_amount_url_uses_only_server_catalog(self):
        self.assertIn("create_kaspi_credit_payment(p_product_id text)", MIGRATION)
        self.assertIn("x5_credits_1000_v2", MIGRATION)
        self.assertIn("x5_credits_5000_v2", MIGRATION)
        self.assertIn("'&amount=' || trunc(v_amount, 2)::text", MIGRATION)
        self.assertIn("constraint kaspi_credit_catalog_match", MIGRATION)
        self.assertNotIn("p_amount_kzt", MIGRATION)

    def test_provider_callback_is_idempotent_and_service_role_only(self):
        self.assertIn("auth.role() <> 'service_role'", MIGRATION)
        self.assertIn("where txn_id = p_txn_id", MIGRATION)
        self.assertIn("for update", MIGRATION)
        self.assertIn("round(p_amount, 2) <> v_payment.amount_kzt", MIGRATION)
        self.assertIn("coalesce(credits, 0) + v_payment.credits", MIGRATION)
        self.assertIn("apply_kaspi_provider_command", PROVIDER)

    def test_native_client_maps_store_products_and_polls_server(self):
        self.assertIn("x5_credits_1000_v2", SERVICE)
        self.assertIn("x5_credits_2000_v2", SERVICE)
        self.assertIn("x5_credits_5000_v2", SERVICE)
        self.assertIn("create_kaspi_credit_payment", SERVICE)
        self.assertIn("get_kaspi_credit_payment", SERVICE)
        self.assertIn("pollKaspiPaymentUntilFinished", PAYWALL)
        self.assertIn("pendingKaspiPaymentID", PAYWALL)
        self.assertIn("openURL(payment.paymentUrl)", PAYWALL)

    def test_internal_testflight_access_is_explicitly_limited(self):
        self.assertIn("KaspiInternalBetaAccess", SERVICE)
        self.assertIn("KaspiInternalBetaAccess.isAllowed(userID: auth.userId)", PAYWALL)
        self.assertIn("credit_store_payment_kaspi", PAYWALL)

    def test_credit_pack_has_one_buy_button_then_payment_method_picker(self):
        pack_card = PAYWALL.split("private func packCard", 1)[1].split(
            "private func buyViaStore", 1
        )[0]
        self.assertEqual(pack_card.count("Button {"), 1)
        self.assertIn("paymentMethodPack = pack", pack_card)
        self.assertIn("confirmationDialog", PAYWALL)
        self.assertIn("credit_store_payment_card", PAYWALL)
        self.assertIn("credit_store_payment_kaspi", PAYWALL)
        self.assertIn("credit_store_payment_apple_pay", PAYWALL)
        self.assertNotIn("credit_store_kaspi_buy", pack_card)

    def test_refund_reverses_credits_only_once(self):
        self.assertIn("refund_kaspi_credit_payment", MIGRATION)
        self.assertIn("status = 'refunded'", MIGRATION)
        self.assertIn("coalesce(credits, 0) - v_payment.credits", MIGRATION)
        self.assertIn("already_refunded", MIGRATION)


if __name__ == "__main__":
    unittest.main()
