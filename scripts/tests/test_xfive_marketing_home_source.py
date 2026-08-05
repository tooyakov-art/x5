from pathlib import Path
import plistlib
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / "X5" / "Views" / "Home" / "HomeView.swift"
TAB_VIEW = ROOT / "X5" / "Views" / "AppTabView.swift"
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

        self.assertIn('.navigationTitle("X five marketing")', home)
        self.assertIn('.navigationTitle("X five marketing")', main)
        self.assertNotIn("X Five AI Studio", home)
        self.assertNotIn("X5 AI", home)
        self.assertEqual(info["CFBundleDisplayName"], "X five marketing")
        self.assertIn("CFBundleDisplayName: X five marketing", project)
        self.assertIn("PRODUCT_NAME: X five marketing", project)
        self.assertEqual(store_name, "X five marketing")

    def test_home_rejects_full_screen_raster_mockups_and_crop_layouts(self):
        home = HOME.read_text(encoding="utf-8")

        for forbidden in (
            "HomeApprovedReference",
            "ApprovedHomeCrop",
            "HomeApprovedLayout",
            "ApprovedArtworkButton",
            "TrendArtworkCard",
            "BusinessArtworkButton",
            "CGRect(x:",
        ):
            self.assertNotIn(forbidden, home)

        for required in (
            "struct NativeHomeHeroCard",
            "struct NativeHomePromoCard",
            "struct NativeHomeTrendCard",
            "struct NativeHomeBusinessCard",
            "Image(slide.assetName)",
            "Text(slide.title)",
            "Text(slide.subtitle)",
            'Text("Создать")',
        ):
            self.assertIn(required, home)

    def test_primary_hero_opens_existing_image_generator(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn('accessibilityIdentifier("x5.home.hero.\\(slide.id).create")', home)
        self.assertIn(
            "action: .imageGeneration(ImageGenerationCatalog.custom)",
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
            "case voiceGeneration",
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

    def test_native_promos_trends_and_business_cards_are_complete(self):
        home = HOME.read_text(encoding="utf-8")

        for text in (
            "Стартап чат",
            "Hub",
            "Измена клубнички",
            "С Токаевым",
            "Карточки WB",
            "Со знаменитостью",
            "Оформление\\nInstagram",
            "Обложки YouTube",
            "Логотипы",
            "Брендбук",
            "AI-инфлюенсер",
            "Карточки товара",
        ):
            self.assertIn(text, home)

        self.assertIn("ScrollView(.horizontal, showsIndicators: false)", home)
        self.assertIn("LazyHStack", home)
        self.assertIn("NativeHomeBusinessCard", home)
        self.assertIn("NativeHomeTrendCard", home)

    def test_header_search_gallery_and_more_are_working_surfaces(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("HomeSearchSheet", home)
        self.assertIn("searchable(text: $query", home)
        self.assertIn("GeneratedGalleryView()", home)
        self.assertIn('accessibilityLabel("Поиск инструментов")', home)
        self.assertIn('accessibilityLabel(loc.t("gen_gallery"))', home)
        self.assertIn('Label("Еще", systemImage: "chevron.right")', home)
        self.assertIn("handle(.videoGeneration)", home)
        self.assertIn('HomeSearchItem(title: "Озвучка"', home)

    def test_hero_is_native_and_has_functional_pages(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("TabView(selection: $activeHeroPage)", home)
        self.assertIn(".tabViewStyle(.page(indexDisplayMode: .never))", home)
        self.assertIn('accessibilityIdentifier("x5.home.hero.\\(slide.id)")', home)
        self.assertIn('assetName: "HomeCoverTargetAds"', home)
        self.assertIn('assetName: "HomeUtilityVideo"', home)
        self.assertIn('assetName: "HomeTrendFruitVideo"', home)
        self.assertIn("action: .videoGeneration", home)
        self.assertIn("action: .liveFruits", home)

    def test_every_trend_keeps_video_preview_and_opens_a_real_route(self):
        home = HOME.read_text(encoding="utf-8")

        self.assertIn("handle(item.action)", home)
        self.assertIn('accessibilityIdentifier("x5.home.trend.\\(item.id)")', home)
        self.assertIn('accessibilityIdentifier("x5.home.trend.\\(item.id).preview")', home)
        self.assertIn('id: "strawberry"', home)
        self.assertIn("action: .liveFruits", home)
        self.assertIn('id: "wildberries"', home)
        self.assertIn('action: imageAction("product_cards")', home)

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

    def test_system_tab_bar_is_native_and_never_replaced(self):
        source = TAB_VIEW.read_text(encoding="utf-8")

        self.assertIn("TabView(selection: $selectedTab)", source)
        self.assertIn(".tint(X5Style.blue)", source)
        self.assertNotIn("X5BottomTabBar", source)
        self.assertNotIn(".toolbar(.hidden, for: .tabBar)", source)
        self.assertNotIn(".safeAreaInset(edge: .bottom", source)
        self.assertNotIn("itemCenters", source)
        self.assertNotIn("GeometryReader", source)
        for key in ("tab_home", "tab_courses", "tab_chats", "tab_hub", "tab_profile"):
            self.assertIn(f'return "{key}"', source)
        self.assertEqual(source.count(".tabItem"), 5)
        self.assertIn("enum X5AppTab: Int, CaseIterable, Identifiable", source)
        self.assertNotIn("private var selectedContent", source)


if __name__ == "__main__":
    unittest.main()
