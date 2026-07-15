import XCTest
@testable import X5

final class HubTaskBrowseStateTests: XCTestCase {
    func testInitialStateShowsCategoryTiles() {
        let state = HubTaskBrowseState()

        XCTAssertFalse(state.isShowingResults)
        XCTAssertNil(state.selectedCategoryId)
    }

    func testAllResultsCanReturnToCategoryTiles() {
        var state = HubTaskBrowseState()

        state.showAllResults()
        XCTAssertTrue(state.isShowingResults)
        XCTAssertNil(state.selectedCategoryId)

        state.showCategories()
        XCTAssertFalse(state.isShowingResults)
        XCTAssertNil(state.selectedCategoryId)
    }

    func testCategoryResultsCanReturnToCategoryTiles() {
        var state = HubTaskBrowseState()

        state.showResults(for: "marketing")
        XCTAssertTrue(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryId, "marketing")

        state.showCategories()
        XCTAssertFalse(state.isShowingResults)
        XCTAssertNil(state.selectedCategoryId)
    }
}
