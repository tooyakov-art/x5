import json
import tempfile
import unittest
from pathlib import Path

from scripts.export_app_analytics import base_snapshot, parse_number


class ExportAppAnalyticsTests(unittest.TestCase):
    def test_parse_number_accepts_store_report_formats(self):
        self.assertEqual(parse_number("1,234"), 1234)
        self.assertEqual(parse_number("12,50"), 12.5)
        self.assertEqual(parse_number(" 7 "), 7)
        self.assertIsNone(parse_number(""))

    def test_public_snapshot_has_expected_contract_and_no_pii(self):
        snapshot = base_snapshot()
        encoded = json.dumps(snapshot, ensure_ascii=False).lower()

        self.assertEqual(snapshot["schemaVersion"], 1)
        self.assertIn("overview", snapshot)
        self.assertIn("sources", snapshot)
        self.assertNotIn("email", encoded)
        self.assertNotIn("userid", encoded)
        self.assertNotIn("transactionid", encoded)
        self.assertNotIn("purchasetoken", encoded)

    def test_checked_in_snapshot_is_valid_json(self):
        path = Path(__file__).resolve().parents[2] / "analytics-data" / "latest.json"
        snapshot = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(snapshot["schemaVersion"], 1)
        self.assertIsInstance(snapshot["builds"], list)


if __name__ == "__main__":
    unittest.main()
