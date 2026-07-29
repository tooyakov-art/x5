import XCTest
@testable import X5

final class HomeMotionPolicyTests: XCTestCase {
    func testMotionCatalogAnimatesOnlyTheHeroAndVideoMarkedMedia() {
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeCoverTargetAds", demoMode: false),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionStudio"),
                posterAssetName: "HomeMotionStudioPoster"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeTrendFruitVideo", demoMode: false),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionFruit"),
                posterAssetName: "HomeMotionFruitPoster"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeTrendLiveVideo", demoMode: false),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionStudio"),
                posterAssetName: "HomeMotionStudioPoster"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeUtilityVideo", demoMode: false),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionStudio"),
                posterAssetName: "HomeMotionStudioPoster"
            )
        )
        XCTAssertNil(HomeMotionCatalog.asset(for: "HomeTrendPost", demoMode: false))
        XCTAssertNil(HomeMotionCatalog.asset(for: "HomeCoverYoutube", demoMode: false))
    }

    func testDemoUsesSeedreamOnlyForTheImageGenerationHero() throws {
        let seedreamURL = try XCTUnwrap(
            URL(
                string: "https://cdn.higgsfield.ai/card/"
                    + "83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4"
            )
        )
        let videoGenerationURL = try XCTUnwrap(
            URL(string: "https://static.higgsfield.ai/ai-video-v2/01-mini.mp4")
        )
        let voiceGenerationURL = try XCTUnwrap(
            URL(
                string: "https://static.higgsfield.ai/flow-medias/"
                    + "create-audio-22-07-2026.mp4"
            )
        )

        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeCoverTargetAds", demoMode: true),
            HomeMotionAsset(
                source: .remote(url: seedreamURL),
                posterAssetName: "HomeCoverTargetAds"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeTrendFruitVideo", demoMode: true),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionFruit"),
                posterAssetName: "HomeMotionFruitPoster"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeTrendLiveVideo", demoMode: true),
            HomeMotionAsset(
                source: .remote(url: videoGenerationURL),
                posterAssetName: "HomeTrendLiveVideo"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeUtilityVideo", demoMode: true),
            HomeMotionAsset(
                source: .remote(url: videoGenerationURL),
                posterAssetName: "HomeUtilityVideo"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeMotionStudioPoster", demoMode: true),
            HomeMotionAsset(
                source: .remote(url: voiceGenerationURL),
                posterAssetName: "HomeMotionStudioPoster"
            )
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeCoverProductCards", demoMode: true),
            nil
        )
        XCTAssertEqual(
            HomeMotionCatalog.asset(for: "HomeCoverTargetAds", demoMode: false),
            HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionStudio"),
                posterAssetName: "HomeMotionStudioPoster"
            )
        )
    }

    func testDemoModeIsAlwaysDisabledForReleaseBuilds() {
        XCTAssertTrue(
            HomeDemoConfiguration.isEnabled(
                isDebugBuild: true,
                environment: [:]
            )
        )
        XCTAssertFalse(
            HomeDemoConfiguration.isEnabled(
                isDebugBuild: true,
                environment: ["X5_HOME_DEMO_MODE": "0"]
            )
        )
        XCTAssertFalse(
            HomeDemoConfiguration.isEnabled(
                isDebugBuild: false,
                environment: ["X5_HOME_DEMO_MODE": "1"]
            )
        )
    }

    func testPlaybackRunsOnlyWhenActiveVisibleForegroundAndMotionAllowed() {
        XCTAssertTrue(
            HomeMotionPlaybackPolicy.shouldPlay(
                isActive: true,
                isVisible: true,
                appIsActive: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            HomeMotionPlaybackPolicy.shouldPlay(
                isActive: false,
                isVisible: true,
                appIsActive: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            HomeMotionPlaybackPolicy.shouldPlay(
                isActive: true,
                isVisible: false,
                appIsActive: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            HomeMotionPlaybackPolicy.shouldPlay(
                isActive: true,
                isVisible: true,
                appIsActive: false,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            HomeMotionPlaybackPolicy.shouldPlay(
                isActive: true,
                isVisible: true,
                appIsActive: true,
                reduceMotion: true
            )
        )
    }
}
