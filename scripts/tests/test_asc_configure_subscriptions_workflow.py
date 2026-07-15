import pathlib
import unittest


WORKFLOW = (
    pathlib.Path(__file__).parents[2]
    / ".github"
    / "workflows"
    / "asc-configure-subscriptions.yml"
)


class SubscriptionWorkflowTests(unittest.TestCase):
    def test_verified_uses_current_store_screenshot_and_replaces_stale_asset(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            "SCREENSHOT_PATH: fastlane/iap-screenshots/x5-credit-store-review.png",
            source,
        )
        self.assertNotIn(
            "SCREENSHOT_PATH: fastlane/iap-screenshots/x5-pro-monthly.jpg",
            source,
        )
        self.assertIn(
            'f"/subscriptionAppStoreReviewScreenshots?filter[subscription]={sub_id}&limit=20"',
            source,
        )
        self.assertIn(
            '"DELETE",\n                          f"/subscriptionAppStoreReviewScreenshots/{stale[\'id\']}"',
            source,
        )


if __name__ == "__main__":
    unittest.main()
