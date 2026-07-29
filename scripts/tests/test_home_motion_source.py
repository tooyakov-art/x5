from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
LOOPING_VIDEO = ROOT / "X5" / "Views" / "Home" / "LoopingVideo.swift"
HOME_VIEW = ROOT / "X5" / "Views" / "Home" / "HomeView.swift"
PROJECT = ROOT / "project.yml"
SOURCES = ROOT / "THIRD_PARTY_SOURCES.md"
MOTION_DIR = ROOT / "X5" / "Resources" / "HomeMotion"
ASSETS = ROOT / "X5" / "Assets.xcassets"


class HomeMotionSourceTests(unittest.TestCase):
    def test_loop_uses_one_plain_avplayer_and_never_the_crashing_queue_looper(self):
        source = LOOPING_VIDEO.read_text(encoding="utf-8")

        self.assertIn("AVPlayer(playerItem: item)", source)
        self.assertIn(".AVPlayerItemDidPlayToEndTime", source)
        self.assertIn("seek(to: .zero)", source)
        self.assertNotIn("AVQueuePlayer", source)
        self.assertNotIn("AVPlayerLooper", source)

    def test_loop_pauses_offscreen_and_in_background_with_a_static_poster(self):
        source = LOOPING_VIDEO.read_text(encoding="utf-8")

        self.assertIn("@Environment(\\.scenePhase)", source)
        self.assertIn("@Environment(\\.accessibilityReduceMotion)", source)
        self.assertIn("HomeMotionPlaybackPolicy.shouldPlay(", source)
        self.assertIn("isVisible", source)
        self.assertIn("player?.pause()", source)
        self.assertIn("Image(posterAssetName)", source)

    def test_home_only_activates_the_visible_hero_and_video_marked_cards(self):
        source = HOME_VIEW.read_text(encoding="utf-8")

        self.assertIn("pageIndex: index", source)
        self.assertIn("isMotionActive: activePage == pageIndex", source)
        self.assertGreaterEqual(
            source.count("CardMedia(assetName: item.assetName, isMotionActive: item.showsPlay)"),
            2,
        )

    def test_debug_demo_uses_seedream_only_for_image_generation_hero(self):
        source = LOOPING_VIDEO.read_text(encoding="utf-8")

        self.assertIn("enum HomeDemoConfiguration", source)
        self.assertIn("X5_HOME_DEMO_MODE", source)
        self.assertIn(
            "https://cdn.higgsfield.ai/card/"
            "83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4",
            source,
        )
        self.assertIn(
            'imageAssetName == "HomeCoverTargetAds"',
            source,
        )
        self.assertIn(
            'imageAssetName == "HomeTrendLiveVideo"',
            source,
        )
        self.assertIn(
            'imageAssetName == "HomeUtilityVideo"',
            source,
        )
        self.assertIn("demoMode: Bool = HomeDemoConfiguration.isEnabled", source)
        self.assertIn("#if DEBUG", source)
        self.assertIn("#else", source)

        seedream_url = (
            "https://cdn.higgsfield.ai/card/"
            "83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4"
        )
        self.assertEqual(source.count(seedream_url), 1)
        video_generation_url = (
            "https://static.higgsfield.ai/ai-video-v2/01-mini.mp4"
        )
        self.assertEqual(source.count(video_generation_url), 1)
        voice_generation_url = (
            "https://static.higgsfield.ai/flow-medias/"
            "create-audio-22-07-2026.mp4"
        )
        self.assertEqual(source.count(voice_generation_url), 1)
        self.assertIn(
            'imageAssetName == "HomeMotionStudioPoster"',
            source,
        )
        for unrelated_landing_video in (
            "f3b62e1c-57dc-4d35-a70a-6e15aa487959",
            "9a59ea96-b8be-4602-b527-98b25b65d6cb",
            "09a449b1-d36b-4f5d-9283-2c9f9a785dd8",
            "2c623c35-129a-47eb-8797-7174a6063daa",
        ):
            self.assertNotIn(unrelated_landing_video, source)

    def test_demo_video_is_streamed_and_not_bundled_into_the_app(self):
        source = LOOPING_VIDEO.read_text(encoding="utf-8")

        self.assertIn("enum HomeMotionSource", source)
        self.assertIn("case bundled(resourceName: String)", source)
        self.assertIn("case remote(url: URL)", source)
        self.assertIn("HomeLoopingVideoController(source: source)", source)

        bundled_names = {path.name for path in MOTION_DIR.glob("*.mp4")}
        self.assertEqual(
            bundled_names,
            {"HomeMotionStudio.mp4", "HomeMotionFruit.mp4"},
        )

    def test_optimized_loops_and_posters_are_bundled(self):
        expected_videos = {
            "HomeMotionStudio.mp4": 1_500_000,
            "HomeMotionFruit.mp4": 1_500_000,
        }
        for filename, maximum_bytes in expected_videos.items():
            path = MOTION_DIR / filename
            self.assertTrue(path.is_file(), filename)
            self.assertLess(path.stat().st_size, maximum_bytes, filename)
            self.assertIn(b"ftyp", path.read_bytes()[:32], filename)

        for asset_name in ("HomeMotionStudioPoster", "HomeMotionFruitPoster"):
            imageset = ASSETS / f"{asset_name}.imageset"
            self.assertTrue((imageset / "Contents.json").is_file(), asset_name)
            posters = list(imageset.glob("*.jpg"))
            self.assertEqual(len(posters), 1, asset_name)
            self.assertLess(posters[0].stat().st_size, 200_000, asset_name)

        project = PROJECT.read_text(encoding="utf-8")
        self.assertIn("- path: X5/Resources/HomeMotion", project)

    def test_pexels_provenance_and_license_are_recorded(self):
        sources = SOURCES.read_text(encoding="utf-8")

        self.assertIn(
            "https://www.pexels.com/video/"
            "digital-projection-of-abstract-geometrical-lines-3129671/",
            sources,
        )
        self.assertIn(
            "https://www.pexels.com/video/"
            "close-up-view-of-fruits-in-a-bowl-6989164/",
            sources,
        )
        self.assertIn("https://www.pexels.com/legal-pages/license/", sources)
        self.assertIn("Retrieved: 2026-07-26", sources)
        self.assertIn("H.264", sources)
        self.assertIn("audio removed", sources)

    def test_higgsfield_demo_provenance_and_release_boundary_are_recorded(self):
        sources = SOURCES.read_text(encoding="utf-8")

        self.assertIn("Seedream 5.0 Pro", sources)
        self.assertIn("https://higgsfield.ai/ai/image?model=seedream_v5_pro", sources)
        self.assertIn(
            "https://cdn.higgsfield.ai/card/"
            "83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4",
            sources,
        )
        self.assertIn("https://higgsfield.ai/ai-video", sources)
        self.assertIn(
            "https://static.higgsfield.ai/ai-video-v2/01-mini.mp4",
            sources,
        )
        self.assertIn(
            "https://static.higgsfield.ai/flow-medias/"
            "create-audio-22-07-2026.mp4",
            sources,
        )
        self.assertIn("AI voiceovers & voice change", sources)
        self.assertIn("debug-only", sources.lower())
        self.assertIn("not bundled", sources.lower())
        self.assertIn("release builds", sources.lower())


if __name__ == "__main__":
    unittest.main()
