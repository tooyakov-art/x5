import importlib.util
import pathlib
import sys
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "asc_submit_credit_packs.py"
SPEC = importlib.util.spec_from_file_location("asc_submit_credit_packs", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(SCRIPT.parent))
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CreditPackSubmissionTests(unittest.TestCase):
    def test_submission_payload_targets_v2_purchase(self):
        payload = MODULE.submission_payload("iap-1")
        self.assertEqual(
            payload["data"]["relationships"]["inAppPurchaseV2"]["data"],
            {"type": "inAppPurchases", "id": "iap-1"},
        )

    def test_submit_only_from_ready_to_submit(self):
        self.assertTrue(
            MODULE.should_submit("READY_TO_SUBMIT", action="submit")
        )
        for state in ("APPROVED", "WAITING_FOR_REVIEW", "IN_REVIEW"):
            with self.subTest(state=state):
                self.assertFalse(
                    MODULE.should_submit(state, action="submit")
                )

    def test_audit_never_mutates(self):
        self.assertFalse(
            MODULE.should_submit("MISSING_METADATA", action="audit")
        )

    def test_unsafe_submit_state_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "MISSING_METADATA"):
            MODULE.should_submit("MISSING_METADATA", action="submit")


if __name__ == "__main__":
    unittest.main()
