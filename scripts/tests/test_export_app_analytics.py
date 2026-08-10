import json
import unittest

from scripts.export_app_analytics import base_snapshot, parse_number, store_metric_rows


class ExportAppAnalyticsTests(unittest.TestCase):
    def test_parse_number_accepts_store_report_formats(self):
        self.assertEqual(parse_number("1,234"), 1234)
        self.assertEqual(parse_number("12,50"), 12.5)
        self.assertEqual(parse_number(" 7 "), 7)
        self.assertIsNone(parse_number(""))

    def test_snapshot_has_expected_contract_and_no_pii(self):
        snapshot = base_snapshot()
        encoded = json.dumps(snapshot, ensure_ascii=False).lower()

        self.assertEqual(snapshot["schemaVersion"], 1)
        self.assertIn("overview", snapshot)
        self.assertIn("sources", snapshot)
        self.assertNotIn("email", encoded)
        self.assertNotIn("userid", encoded)
        self.assertNotIn("transactionid", encoded)
        self.assertNotIn("purchasetoken", encoded)

    def test_store_rows_are_private_table_shape(self):
        snapshot = base_snapshot()
        snapshot["trend"] = [{"date": "2026-08-09", "downloads": 8, "installs": 6, "purchases": 2, "sessions": 9}]
        snapshot["overview"]["revenue"] = {"value": 19.98, "currency": "USD", "status": "ready"}
        rows = store_metric_rows(snapshot)
        self.assertEqual(rows[0]["provider"], "apple")
        self.assertEqual(rows[0]["platform"], "ios")
        self.assertEqual(rows[0]["revenue"], 19.98)
        self.assertNotIn("email", json.dumps(rows).lower())


if __name__ == "__main__":
    unittest.main()
