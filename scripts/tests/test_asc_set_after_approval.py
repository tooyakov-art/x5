import importlib.util
import pathlib
import unittest


SCRIPT_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "asc_set_after_approval.py"
)
WORKFLOW_PATH = (
    pathlib.Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "asc-release-audit.yml"
)


def load_script():
    spec = importlib.util.spec_from_file_location(
        "asc_set_after_approval", SCRIPT_PATH
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class SetAfterApprovalContractTests(unittest.TestCase):
    def test_guarded_release_type_script_exists(self):
        self.assertTrue(
            SCRIPT_PATH.exists(),
            "A guarded AFTER_APPROVAL patch script is required",
        )

    def test_patches_only_release_type_and_confirms_unchanged_review_state(self):
        module = load_script()
        self.assertTrue(hasattr(module, "set_after_approval"))

        class FakeClient:
            def __init__(self):
                self.updates = []
                self.version = {
                    "id": "version-116",
                    "attributes": {
                        "versionString": "1.1.6",
                        "platform": "IOS",
                        "appStoreState": "WAITING_FOR_REVIEW",
                        "releaseType": "MANUAL",
                    },
                }

            def find_app_id(self, bundle_id):
                self.bundle_id = bundle_id
                return "app-1"

            def list_versions(self, app_id):
                self.app_id = app_id
                return [self.version]

            def get_attached_build(self, version_id):
                self.version_id = version_id
                return {
                    "id": "build-228",
                    "attributes": {
                        "version": "228",
                        "processingState": "VALID",
                        "expired": False,
                    },
                }

            def update_release_type(self, version_id, release_type):
                self.updates.append((version_id, release_type))
                self.version["attributes"]["releaseType"] = release_type

            def get_version(self, version_id):
                return self.version

        client = FakeClient()
        result = module.set_after_approval(
            client,
            bundle_id="com.x5studio.app",
            version_string="1.1.6",
            build_number="228",
        )

        self.assertEqual(client.updates, [("version-116", "AFTER_APPROVAL")])
        self.assertEqual(result["releaseType"], "AFTER_APPROVAL")
        self.assertEqual(result["appStoreState"], "WAITING_FOR_REVIEW")

        module.set_after_approval(
            client,
            bundle_id="com.x5studio.app",
            version_string="1.1.6",
            build_number="228",
        )
        self.assertEqual(len(client.updates), 1)

    def test_rejects_unexpected_version_build_or_review_state_before_patch(self):
        module = load_script()

        class UnsafeClient:
            updates = []

            def find_app_id(self, _bundle_id):
                return "app-1"

            def list_versions(self, _app_id):
                return [
                    {
                        "id": "version-116",
                        "attributes": {
                            "versionString": "1.1.6",
                            "platform": "IOS",
                            "appStoreState": "IN_REVIEW",
                            "releaseType": "MANUAL",
                        },
                    }
                ]

            def get_attached_build(self, _version_id):
                return {
                    "id": "build-228",
                    "attributes": {
                        "version": "228",
                        "processingState": "VALID",
                        "expired": False,
                    },
                }

            def update_release_type(self, version_id, release_type):
                self.updates.append((version_id, release_type))

            def get_version(self, _version_id):
                raise AssertionError("GET after PATCH must not run when guards fail")

        client = UnsafeClient()
        for version, build in (
            ("1.1.5", "228"),
            ("1.1.6", "226"),
            ("1.1.6", "228"),
        ):
            with self.subTest(version=version, build=build):
                with self.assertRaises(ValueError):
                    module.set_after_approval(
                        client,
                        bundle_id="com.x5studio.app",
                        version_string=version,
                        build_number=build,
                    )
        self.assertEqual(client.updates, [])

    def test_release_audit_workflow_exposes_explicit_guarded_action(self):
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        self.assertIn('default: "audit"', workflow)
        self.assertIn("set_after_approval", workflow)
        self.assertIn("scripts/asc_set_after_approval.py", workflow)
        self.assertIn('EXPECTED_VERSION: "1.1.6"', workflow)
        self.assertIn('EXPECTED_BUILD: "228"', workflow)


if __name__ == "__main__":
    unittest.main()
