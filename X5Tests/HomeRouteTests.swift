import XCTest
@testable import X5

final class HomeRouteTests: XCTestCase {
    func testPrimaryRoutesHaveStableIdentifiers() {
        XCTAssertEqual(
            HomeRoute.imageGeneration(ImageGenerationCatalog.custom).id,
            "image_generation:custom"
        )
        XCTAssertEqual(HomeRoute.startupChat.id, "startup_chat")
        XCTAssertEqual(HomeRoute.hub.id, "hub")
        XCTAssertEqual(HomeRoute.videoGeneration.id, "video_generation")
        XCTAssertEqual(HomeRoute.liveFruits.id, "live_fruits")
        XCTAssertEqual(HomeRoute.voiceGeneration.id, "voice_generation")
    }

    func testImageRoutesKeepTheirSelectedCategory() {
        let category = ImageGenerationCatalog.categories[0]

        guard case .imageGeneration(let routedCategory) = HomeRoute.imageGeneration(category) else {
            return XCTFail("Expected an image-generation route")
        }

        XCTAssertEqual(routedCategory, category)
    }
}
