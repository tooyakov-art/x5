from hashlib import sha256
from pathlib import Path
import plistlib
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / "X5" / "Views" / "Home" / "HomeView.swift"
TAB_VIEW = ROOT / "X5" / "Views" / "AppTabView.swift"
REFERENCE = (
    ROOT
    / "X5"
    / "Assets.xcassets"
    / "HomeApprovedReference.imageset"
    / "HomeApprovedReference.png"
)
ENCRYPTED_REFERENCE = ROOT / "PrivateAssets" / "HomeApprovedReference.png.enc"


class XFiveMarketingHomeSourceTests(unittest.TestCase):
    def test_visible_brand_uses_exact_client_name(self):
        home = HOME.read_text(encoding="utf-8")
        main = (ROOT / "X5" / "Views" / "MainView.swift").read_text(
            encoding="utf-8"
        )
        with (ROOT / "X5" / "Info.plist").open("rb") as plist_file:
            info = plistlib.load(plist_file)
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        store_name = (
            ROOT / "fastlane" / "metadata" / "en-US" / "name.txt"
        ).read_text(encoding="utf-8").strip()

        self.assertIn('Text("X five marketing")', home)
        self.assertIn('.navigationTitle("X five marketing")', main)
        self.assertNotIn("X Five AI Studio", home)
        self.assertNotIn("X5 AI", home)
        self.assertEqual(info["CFBundleDisplayName"], "X five marketing")
        self.assertIn("CFBundleDisplayName: X five marketing", project)
        self.assertIn("PRODUCT_NAME: X five marketing", project)
        self.assertEqual(store_name, "X five marketing")

    def test_approved_mockup_is_the_exact_release_art_source(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertTrue(REFERENCE.is_file())
        self.assertTrue(ENCRYPTED_REFERENCE.is_file())
        self.assertEqual(
            sha256(REFERENCE.read_bytes()).hexdigest(),
            "c77a8588b7c98e831fe6e915c9bba83c9ee1f835b0452ef05455f8aa107f651b",
        )
        self.assertIn('Image("HomeApprovedReference")', home)
        self.assertIn("struct ApprovedHomeCrop", home)
        self.assertIn("static let referenceSize = CGSize(width: 740, height: 1600)", home)
        self.assertIn("static let hero = CGRect(x: 28, y: 145", home)
        self.assertNotIn("HomeCoverTargetAds", home)
        self.assertNotIn("HomeTrendNanoBanana", home)

    def test_primary_hero_opens_existing_image_generator(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn('accessibilityLabel("Генерация изображений. Создать")', home)
        self.assertIn(
            "handle(.imageGeneration(ImageGenerationCatalog.custom))",
            home,
        )
        self.assertIn("ImageGeneratorView(category: category", home)

    def test_home_routes_are_explicit_and_hub_uses_existing_tab_switch(self):
        home = HOME.read_text(encoding="utf-8")

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
        self.assertRegex(home, r"case \.startupChat:\s+StartupChatView\(\)")
        self.assertRegex(home, r"case \.liveFruits:\s+LiveFruitsView\(\)")
        self.assertIn("VideoGeneratorView()", home)

    def test_approved_promos_trends_and_business_cards_are_complete(self):
        home = HOME.read_text(encoding="utf-8")

        for text in (
            "Стартап чат",
            "Hub",
            "Измена клубнички",
            "С Токаевым",
            "Карточки WB",
            "Со знаменитостью",
            "Оформление Instagram",
            "Обложки YouTube",
            "Логотипы",
            "Брендбук",
            "AI-инфлюенсер",
            "Карточки товара",
        ):
            self.assertIn(text, home)

        self.assertIn("HomeApprovedLayout.trendRailWidth", home)
        self.assertIn("static let trendGaps: [CGFloat] = [9, 11, 7]", home)
        self.assertIn("width: item.crop.width * scale", home)
        self.assertGreaterEqual(home.count("HStack(spacing: 5)"), 3)
        self.assertEqual(home.count("BusinessArtworkButton("), 6)

    def test_approved_crop_geometry_and_outer_spacing_are_literal(self):
        home = HOME.read_text(encoding="utf-8")

        for exact in (
            ".padding(.horizontal, 16.65)",
            ".padding(.top, 42)",
            ".offset(y: 0.6)",
            ".offset(x: 1.2)",
            ".padding(.top, 3.4)",
            "VStack(alignment: .leading, spacing: 5.2)",
            "static let hero = CGRect(x: 28, y: 145, width: 684, height: 354)",
            "static let startupPromo = CGRect(x: 29, y: 510, width: 339, height: 90)",
            "static let hubPromo = CGRect(x: 376, y: 510, width: 337, height: 90)",
            "static let trendStrawberry = CGRect(x: 28, y: 649, width: 176, height: 265)",
            "static let trendTokayev = CGRect(x: 213, y: 649, width: 188, height: 265)",
            "static let trendWildberries = CGRect(x: 412, y: 649, width: 160, height: 265)",
            "static let trendCelebrity = CGRect(x: 579, y: 649, width: 133, height: 265)",
            "static let instagramBanner = CGRect(x: 28, y: 969, width: 684, height: 204)",
            "static let youtube = CGRect(x: 28, y: 1181, width: 338, height: 129)",
            "static let logo = CGRect(x: 374, y: 1181, width: 338, height: 129)",
            "static let brandbook = CGRect(x: 28, y: 1319, width: 338, height: 120)",
            "static let influencer = CGRect(x: 374, y: 1319, width: 338, height: 120)",
            "static let productCards = CGRect(x: 28, y: 1448, width: 684, height: 96)",
        ):
            self.assertIn(exact, home)

    def test_header_search_gallery_and_more_are_working_surfaces(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("HomeSearchSheet", home)
        self.assertIn("searchable(text: $query", home)
        self.assertIn("GeneratedGalleryView()", home)
        self.assertIn('accessibilityLabel("Поиск инструментов")', home)
        self.assertIn('accessibilityLabel(loc.t("gen_gallery"))', home)
        self.assertIn('Text("Еще")', home)
        self.assertIn('Image(systemName: "chevron.right")', home)
        self.assertIn("handle(.videoGeneration)", home)

    def test_search_waits_for_sheet_dismissal_before_routing(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("@State private var pendingSearchRoute: HomeRoute?", home)
        self.assertIn("onDismiss: completePendingSearchRoute", home)
        self.assertIn("pendingSearchRoute = route", home)
        self.assertIn("showingSearch = false", home)

    def test_motion_restrictions_never_show_a_false_playing_state(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("@Environment(\\.accessibilityReduceMotion)", home)
        self.assertIn("ProcessInfo.processInfo.isLowPowerModeEnabled", home)
        self.assertIn("motionPreviewAllowed && activeTrendVideoID == item.id", home)
        self.assertIn("if !isAllowed { activeTrendVideoID = nil }", home)
        self.assertIn("handle(.videoGeneration)", home)

    def test_custom_tab_bar_matches_approved_compact_layout(self):
        source = TAB_VIEW.read_text(encoding="utf-8")

        self.assertIn("X5BottomTabBar", source)
        self.assertIn("ZStack(alignment: .bottom)", source)
        self.assertIn("TabView(selection: $selectedTab)", source)
        self.assertIn(".toolbar(.hidden, for: .tabBar)", source)
        self.assertGreaterEqual(
            source.count(".toolbar(.hidden, for: .tabBar)"),
            6,
            "Every tab content must hide the native iOS 26 tab bar.",
        )
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", source)
        self.assertIn(".ignoresSafeArea(.container, edges: .bottom)", source)
        self.assertIn(
            "private let itemCenters: [CGFloat] = [138, 260, 372, 473, 576]",
            source,
        )
        for key in ("tab_home", "tab_courses", "tab_chats", "tab_hub", "tab_profile"):
            self.assertIn(f'titleKey: "{key}"', source)
        self.assertIn("Text(loc.t(item.titleKey))", source)
        self.assertIn("@ScaledMetric(relativeTo: .caption2)", source)
        self.assertIn("@ScaledMetric(relativeTo: .body)", source)
        self.assertNotIn(".tabItem", source)
        self.assertNotIn("private var selectedContent", source)
        self.assertIn(".frame(minHeight: 44, alignment: .bottom)", source)


if __name__ == "__main__":
    unittest.main()
