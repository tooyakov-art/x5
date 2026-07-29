from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / "X5" / "Services" / "VoiceGenerationService.swift"
VIEW = ROOT / "X5" / "Views" / "Home" / "VoiceGeneratorView.swift"
HOME = ROOT / "X5" / "Views" / "Home" / "HomeView.swift"
SOURCES = ROOT / "THIRD_PARTY_SOURCES.md"
WORKFLOW = ROOT / ".github" / "workflows" / "ios-course-ci.yml"


class IOSVoiceGenerationSourceTests(unittest.TestCase):
    def test_server_only_service_uses_authenticated_idempotent_edge_contract(self):
        self.assertTrue(SERVICE.is_file())
        source = SERVICE.read_text(encoding="utf-8")

        self.assertIn("functions/v1/generate-voice", source)
        self.assertIn('"Idempotency-Key"', source)
        self.assertIn('"request_id"', source)
        self.assertIn('"language_code"', source)
        self.assertNotRegex(source, r"FAL_KEY|fal\.run|elevenlabs")
        self.assertIn("VoiceGenerationLocalStore", source)
        self.assertIn("pendingRequestID", source)

    def test_home_routes_sound_to_real_voice_generator(self):
        self.assertTrue(VIEW.is_file())
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("case voiceGeneration", home)
        self.assertIn('return "voice_generation"', home)
        self.assertIn('action: .voiceGeneration', home)
        self.assertIn("VoiceGeneratorView()", home)

    def test_voice_ui_has_native_input_playback_and_sharing(self):
        self.assertTrue(VIEW.is_file())
        source = VIEW.read_text(encoding="utf-8")

        self.assertIn("TextEditor", source)
        self.assertIn("Picker", source)
        self.assertIn("AVPlayer", source)
        self.assertIn("ShareLink", source)
        self.assertIn("VoiceGenerationService", source)
        self.assertIn("applyCreditsRemaining", source)

    def test_ci_and_provenance_include_voice_generation(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        sources = SOURCES.read_text(encoding="utf-8")

        self.assertIn("supabase/functions/generate-voice", workflow)
        self.assertIn("voice_generation_backend_contract_test.mjs", workflow)
        self.assertIn(
            "https://fal.ai/models/fal-ai/elevenlabs/tts/eleven-v3",
            sources,
        )
        self.assertIn("Retrieved: 2026-07-26", sources)


if __name__ == "__main__":
    unittest.main()
