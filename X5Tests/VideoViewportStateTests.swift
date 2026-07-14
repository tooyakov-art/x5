import XCTest
@testable import X5

final class VideoViewportStateTests: XCTestCase {
    func testInitialStateUsesAnUnzoomedCenteredViewport() {
        let state = VideoViewportState()

        XCTAssertEqual(state.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(state.translationX, 0, accuracy: 0.000_001)
        XCTAssertEqual(state.translationY, 0, accuracy: 0.000_001)
    }

    func testApplyMagnificationKeepsValuesWithinOneAndFour() {
        var state = VideoViewportState()

        state.applyMagnification(0.25)
        XCTAssertEqual(state.scale, 1, accuracy: 0.000_001)

        state.applyMagnification(2.5)
        XCTAssertEqual(state.scale, 2.5, accuracy: 0.000_001)

        state.applyMagnification(8)
        XCTAssertEqual(state.scale, 4, accuracy: 0.000_001)
    }

    func testTranslationIsIgnoredWhileViewportIsNotZoomed() {
        var state = VideoViewportState()

        state.applyTranslation(x: 32, y: -18)

        XCTAssertEqual(state.translationX, 0, accuracy: 0.000_001)
        XCTAssertEqual(state.translationY, 0, accuracy: 0.000_001)
    }

    func testTranslationIsAppliedWhileViewportIsZoomed() {
        var state = VideoViewportState()
        state.applyMagnification(2)

        state.applyTranslation(x: 32, y: -18)

        XCTAssertEqual(state.translationX, 32, accuracy: 0.000_001)
        XCTAssertEqual(state.translationY, -18, accuracy: 0.000_001)
    }

    func testReturningToMinimumMagnificationRecentersViewport() {
        var state = VideoViewportState()
        state.applyMagnification(3)
        state.applyTranslation(x: 40, y: 24)

        state.applyMagnification(1)

        XCTAssertEqual(state.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(state.translationX, 0, accuracy: 0.000_001)
        XCTAssertEqual(state.translationY, 0, accuracy: 0.000_001)
    }

    func testResetRestoresDefaultViewport() {
        var state = VideoViewportState()
        state.applyMagnification(4)
        state.applyTranslation(x: -12, y: 90)

        state.reset()

        XCTAssertEqual(state.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(state.translationX, 0, accuracy: 0.000_001)
        XCTAssertEqual(state.translationY, 0, accuracy: 0.000_001)
    }
}
