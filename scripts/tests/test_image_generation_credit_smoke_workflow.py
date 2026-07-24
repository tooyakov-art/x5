from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "image-generation-credit-smoke.yml"


class ImageGenerationCreditSmokeWorkflowTests(unittest.TestCase):
    def test_service_role_smoke_is_non_mutating_and_checks_the_data_api(self):
        self.assertTrue(WORKFLOW.exists())
        source = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertIn("/rest/v1/rpc/claim_image_generation_request", source)
        self.assertIn('"p_cost_credits": 0', source)
        self.assertIn('payload.get("status") != "invalid_request"', source)
        self.assertNotIn("profiles", source)


if __name__ == "__main__":
    unittest.main()
