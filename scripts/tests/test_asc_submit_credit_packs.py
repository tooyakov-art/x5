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
    def test_iap_version_payload_targets_parent_purchase(self):
        payload = MODULE.iap_version_payload("iap-1")
        self.assertEqual(
            payload["data"]["relationships"]["inAppPurchase"]["data"],
            {"type": "inAppPurchases", "id": "iap-1"},
        )

    def test_review_item_can_attach_iap_version(self):
        payload = MODULE.review_item_payload(
            "submission-1",
            "inAppPurchaseVersion",
            "inAppPurchaseVersions",
            "version-1",
        )
        relationships = payload["data"]["relationships"]
        self.assertEqual(
            relationships["reviewSubmission"]["data"]["id"],
            "submission-1",
        )
        self.assertEqual(
            relationships["inAppPurchaseVersion"]["data"],
            {"type": "inAppPurchaseVersions", "id": "version-1"},
        )

    def test_combined_submission_targets_ios_app(self):
        payload = MODULE.review_submission_payload("app-1")
        self.assertEqual(payload["data"]["attributes"]["platform"], "IOS")
        self.assertEqual(
            payload["data"]["relationships"]["app"]["data"],
            {"type": "apps", "id": "app-1"},
        )

    def test_developer_rejected_iap_version_is_reused(self):
        rejected = {
            "id": "version-1",
            "attributes": {"state": "DEVELOPER_REJECTED"},
        }

        class FakeAPI:
            def list_all(self, path):
                return [rejected]

            def request(self, *args, **kwargs):
                raise AssertionError("must not create a duplicate version")

        self.assertEqual(
            MODULE.ensure_iap_version(FakeAPI(), "iap-1"),
            rejected,
        )

    def test_single_ready_submission_is_reused(self):
        ready = {
            "id": "submission-1",
            "attributes": {"state": "READY_FOR_REVIEW"},
        }
        complete = {
            "id": "submission-2",
            "attributes": {"state": "COMPLETE"},
        }
        self.assertEqual(
            MODULE.single_ready_submission([complete, ready]),
            ready,
        )

    def test_multiple_ready_submissions_fail_closed(self):
        rows = [
            {"id": "one", "attributes": {"state": "READY_FOR_REVIEW"}},
            {"id": "two", "attributes": {"state": "READY_FOR_REVIEW"}},
        ]
        with self.assertRaisesRegex(RuntimeError, "More than one"):
            MODULE.single_ready_submission(rows)

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
