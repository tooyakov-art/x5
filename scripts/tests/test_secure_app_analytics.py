import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class SecureAppAnalyticsSourceTests(unittest.TestCase):
    def test_onboarding_requires_location_and_role(self):
        source = (ROOT / "X5/Views/OnboardingView.swift").read_text(encoding="utf-8")
        for field in (
            '"user_role": role.rawValue',
            '"country_code": countryCode',
            '"city": city.trimmingCharacters',
            '"registration_platform": "ios"',
            '"onboarding_completed_at"',
        ):
            self.assertIn(field, source)
        self.assertIn("case specialist, entrepreneur", source)

    def test_analytics_uses_random_installation_id_and_rpc(self):
        source = (ROOT / "X5/Services/AppAnalyticsService.swift").read_text(encoding="utf-8")
        self.assertIn('UUID()', source)
        self.assertIn('rest/v1/rpc/record_app_event', source)
        self.assertNotIn('identifierForAdvertising', source)
        self.assertNotIn('IDFA', source)

    def test_geonames_dataset_has_supported_cis_countries(self):
        rows = json.loads((ROOT / "X5/Resources/cis-cities.json").read_text(encoding="utf-8"))
        countries = {row["country"] for row in rows}
        self.assertGreater(len(rows), 1000)
        self.assertEqual(countries, {"AM", "AZ", "BY", "GE", "KZ", "KG", "MD", "RU", "TJ", "TM", "UA", "UZ"})

    def test_storekit_entitlement_is_granted_only_by_server(self):
        source = (ROOT / "X5/Services/IAPService.swift").read_text(encoding="utf-8")
        self.assertIn('functions/v1/verify-apple-purchase', source)
        self.assertIn('"transaction_id": String(transaction.id)', source)
        self.assertNotIn('"plan": "pro"', source)
        self.assertNotIn('rest/v1/profiles', source)


if __name__ == "__main__":
    unittest.main()
