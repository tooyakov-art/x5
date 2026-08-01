from pathlib import Path
import plistlib
import unittest


ROOT = Path(__file__).resolve().parents[2]


class XFiveMarketingHomeSourceTests(unittest.TestCase):
    def test_visible_brand_uses_exact_client_name(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )
        main = (ROOT / "X5" / "Views" / "MainView.swift").read_text(
            encoding="utf-8"
        )
        with (ROOT / "X5" / "Info.plist").open("rb") as plist_file:
            info = plistlib.load(plist_file)
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        store_name = (
            ROOT / "fastlane" / "metadata" / "en-US" / "name.txt"
        ).read_text(encoding="utf-8").strip()

        self.assertIn('.navigationTitle("X five marketing")', home)
        self.assertIn('.navigationTitle("X five marketing")', main)
        self.assertNotIn("X Five AI Studio", home)
        self.assertNotIn("X5 AI", home)
        self.assertEqual(info["CFBundleDisplayName"], "X five marketing")
        self.assertIn("CFBundleDisplayName: X five marketing", project)
        self.assertIn("PRODUCT_NAME: X five marketing", project)
        self.assertEqual(store_name, "X five marketing")

    def test_primary_hero_opens_existing_image_generator(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn('title: "Генерация изображений"', home)
        self.assertIn(
            "action: .imageGeneration(ImageGenerationCatalog.custom)",
            home,
        )
        self.assertIn("ImageGeneratorView(category: category", home)

    def test_home_routes_are_explicit_and_hub_uses_existing_tab_switch(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("enum HomeRoute: Hashable, Identifiable", home)
        for route in (
            "case imageGeneration(ImageGenerationCategory)",
            "case startupChat",
            "case hub",
            "case videoGeneration",
            "case liveFruits",
        ):
            self.assertIn(route, home)
        self.assertIn(
            'NotificationCenter.default.post(name: .x5SwitchTab, '
            'object: nil, userInfo: ["tab": "hub"])',
            home,
        )

    def test_home_has_exact_functional_startup_chat_and_hub_promos(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )
        promos = home[
            home.index("private var promos") : home.index("private var promoCards")
        ]

        self.assertEqual(promos.count("HomePromo("), 2)
        self.assertIn('id: "startup_chat"', promos)
        self.assertIn('title: "Стартап чат"', promos)
        self.assertIn("action: .startupChat", promos)
        self.assertIn('id: "hub"', promos)
        self.assertIn('title: "Hub"', promos)
        self.assertIn("action: .hub", promos)
        self.assertRegex(home, r"case \.startupChat:\s+StartupChatView\(\)")
        self.assertIn(
            'NotificationCenter.default.post(name: .x5SwitchTab, '
            'object: nil, userInfo: ["tab": "hub"])',
            home,
        )
        self.assertIn("LazyVGrid(", home)
        self.assertIn("count: 2", home)

    def test_image_and_video_heroes_use_distinct_static_media_surfaces(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn('title: "Генерация изображений"', home)
        self.assertIn('assetName: "HomeCoverTargetAds"', home)
        self.assertIn('title: "Генерация видео"', home)
        self.assertIn('assetName: "HomeUtilityVideo"', home)
        self.assertNotIn('title: "Озвучка и голоса"', home)
        self.assertIn("CardMedia(assetName: slide.assetName, isMotionActive: false)", home)
        self.assertIn(".frame(height: 244)", home)

    def test_video_route_opens_real_generator_instead_of_placeholder(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("VideoGeneratorView()", home)
        self.assertNotIn(
            'developmentTool(id: "video_gen", title: "AI Video"',
            home,
        )

    def test_startup_chat_route_opens_real_assistant(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("StartupChatView()", home)
        self.assertNotIn(
            'developmentTool(id: "startup_chat", title:',
            home,
        )

    def test_live_fruits_route_opens_real_story_builder(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )

        self.assertRegex(
            home,
            r"case \.liveFruits:\s+LiveFruitsView\(\)",
        )
        self.assertNotIn("case .liveFruits, .tool:", home)

    def test_client_supplied_nano_banana_art_is_bundled_and_routes_to_image_generation(self):
        home = (ROOT / "X5" / "Views" / "Home" / "HomeView.swift").read_text(
            encoding="utf-8"
        )
        asset = (
            ROOT
            / "X5"
            / "Assets.xcassets"
            / "HomeTrendNanoBanana.imageset"
            / "HomeTrendNanoBanana.jpg"
        )

        self.assertTrue(asset.is_file())
        self.assertGreater(asset.stat().st_size, 100_000)
        self.assertIn('assetName: "HomeTrendNanoBanana"', home)
        self.assertIn('title: "Nano Banana + GPT Image"', home)
        self.assertIn(
            "action: .imageGeneration(ImageGenerationCatalog.custom)",
            home,
        )
        self.assertIn('item.id == "nano_banana" ? 236 : 148', home)


if __name__ == "__main__":
    unittest.main()
