from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseVersionSourceTests(unittest.TestCase):
    def test_ios_release_version_and_build_are_consistent(self):
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        fastfile = (ROOT / "fastlane" / "Fastfile").read_text(encoding="utf-8")
        review_notes = (
            ROOT / "fastlane" / "metadata" / "review_information" / "notes.txt"
        ).read_text(encoding="utf-8")
        submit_workflow = (
            ROOT / ".github" / "workflows" / "asc-release-submit.yml"
        ).read_text(encoding="utf-8")
        prepare_workflow = (
            ROOT / ".github" / "workflows" / "asc-release-prepare.yml"
        ).read_text(encoding="utf-8")

        marketing_version = re.search(
            r'MARKETING_VERSION:\s*"([^"]+)"', project
        ).group(1)
        build_number = re.search(
            r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', project
        ).group(1)
        fastlane_version = re.search(
            r'APP_VERSION\s*=\s*"([^"]+)"', fastfile
        ).group(1)

        self.assertEqual(marketing_version, "1.1.6")
        self.assertEqual(build_number, "189")
        self.assertEqual(fastlane_version, marketing_version)
        self.assertIn(
            f"Version {marketing_version} build {build_number}",
            review_notes,
        )
        self.assertIn(
            f'EXPECTED_VERSION: "{marketing_version}"',
            submit_workflow,
        )
        self.assertIn(
            f'EXPECTED_BUILD: "{build_number}"',
            submit_workflow,
        )
        self.assertIn(
            f'VERSION: "{marketing_version}"',
            prepare_workflow,
        )
        self.assertIn(
            f'BUILD_NUMBER: "{build_number}"',
            prepare_workflow,
        )

    def test_app_store_review_notes_fit_apple_limit(self):
        notes = (
            ROOT / "fastlane" / "metadata" / "review_information" / "notes.txt"
        ).read_bytes()

        self.assertLessEqual(len(notes), 4000)

    def test_store_metadata_discloses_portfolio_moderation_provider(self):
        description = (
            ROOT / "fastlane" / "metadata" / "en-US" / "description.txt"
        ).read_text(encoding="utf-8")
        notes = (
            ROOT / "fastlane" / "metadata" / "review_information" / "notes.txt"
        ).read_text(encoding="utf-8")
        privacy = (ROOT / "site" / "privacy.html").read_text(encoding="utf-8")

        self.assertIn("OpenAI", description)
        self.assertIn("OpenAI", notes)
        self.assertIn("OpenAI", privacy)
        self.assertIn("portfolio", description.lower())
        self.assertIn("moderation", description.lower())

    def test_submission_declares_user_generated_third_party_content(self):
        fastfile = (ROOT / "fastlane" / "Fastfile").read_text(encoding="utf-8")

        self.assertIn(
            "content_rights_contains_third_party_content: true",
            fastfile,
        )
        self.assertIn("content_rights_has_rights: true", fastfile)


if __name__ == "__main__":
    unittest.main()
