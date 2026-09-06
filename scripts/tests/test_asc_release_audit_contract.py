import pathlib
import re
import unittest


WORKFLOW = (
    pathlib.Path(__file__).parents[2]
    / ".github"
    / "workflows"
    / "asc-release-audit.yml"
).read_text(encoding="utf-8")


class AppStoreReleaseAuditContractTests(unittest.TestCase):
    def test_live_app_store_version_is_a_success_state(self):
        match = re.search(
            r"READY_VERSION_STATES\s*=\s*\{(?P<body>.*?)\n\s*\}",
            WORKFLOW,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        self.assertIn('"READY_FOR_SALE"', match.group("body"))


if __name__ == "__main__":
    unittest.main()
