import XCTest
@testable import X5

final class HubTaskBrowseStateTests: XCTestCase {
    func testInitialStateShowsCategoryTiles() {
        let state = HubTaskBrowseState()

        XCTAssertFalse(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, [])
    }

    func testAllResultsCanReturnToCategoryTiles() {
        var state = HubTaskBrowseState()

        state.showAllResults()
        XCTAssertTrue(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, [])

        state.showCategories()
        XCTAssertFalse(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, [])
    }

    func testCategoryResultsCanReturnToCategoryTiles() {
        var state = HubTaskBrowseState()

        state.showResults(for: "marketing")
        XCTAssertTrue(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, ["marketing"])

        state.showCategories()
        XCTAssertFalse(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, [])
    }

    func testSeveralCategoryFiltersCanBeCombinedAndToggled() {
        var state = HubTaskBrowseState()

        state.showResults(for: "marketing")
        state.toggleResults(for: "ugc")
        state.toggleResults(for: "design")

        XCTAssertEqual(state.selectedCategoryIds, ["marketing", "ugc", "design"])
        XCTAssertTrue(state.includes(categoryId: "ugc"))
        XCTAssertFalse(state.includes(categoryId: "seo"))

        state.toggleResults(for: "marketing")
        XCTAssertEqual(state.selectedCategoryIds, ["ugc", "design"])
    }

    func testNoSelectedCategoryMeansAllTasksMatch() {
        var state = HubTaskBrowseState()

        state.showAllResults()

        XCTAssertTrue(state.includes(categoryId: "marketing"))
        XCTAssertTrue(state.includes(categoryId: "ugc"))
    }

    func testCategoryFilterAppliesEveryManuallySelectedCategory() {
        var state = HubTaskBrowseState()

        state.applyCategoryFilter(["marketing", "ugc", "design"])

        XCTAssertTrue(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, ["marketing", "ugc", "design"])
        XCTAssertTrue(state.includes(categoryId: "marketing"))
        XCTAssertTrue(state.includes(categoryId: "ugc"))
        XCTAssertFalse(state.includes(categoryId: "seo"))
    }

    func testCategoryFilterWithoutASelectionStaysOnGrid() {
        var state = HubTaskBrowseState()

        state.applyCategoryFilter([])

        XCTAssertFalse(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, [])
    }

    func testProfileCategoryFilterUsesEverySavedCategoryAndNormalizesAliases() {
        var state = HubTaskBrowseState()

        state.showResults(forProfileCategories: [
            " Marketing ",
            "target ads",
            "UI/UX",
            "unknown-category"
        ])

        XCTAssertTrue(state.isShowingResults)
        XCTAssertEqual(state.selectedCategoryIds, ["marketing", "targeting", "ui_ux"])
        XCTAssertTrue(state.includes(categoryId: "marketing"))
        XCTAssertTrue(state.includes(categoryId: "targeting"))
        XCTAssertTrue(state.includes(categoryId: "ui_ux"))
        XCTAssertFalse(state.includes(categoryId: "seo"))
    }

    func testProfileCategoryFilterStaysOnGridWhenProfileHasNoKnownCategories() {
        for categories in [nil, [], ["", "unknown-category"]] as [[String]?] {
            var state = HubTaskBrowseState()

            let didApply = state.showResults(forProfileCategories: categories)

            XCTAssertFalse(didApply)
            XCTAssertFalse(state.isShowingResults)
            XCTAssertEqual(state.selectedCategoryIds, [])
        }
    }

    func testProfileCategoryNormalizationReturnsOnlyKnownHubCategoryIds() {
        XCTAssertEqual(
            HubCategories.normalizedIDs(from: ["SMM specialist", "web development", "Game Dev"]),
            ["smm", "web_dev", "gamedev"]
        )
        XCTAssertEqual(HubCategories.normalizedIDs(from: ["unknown", "  "]), [])
    }

    func testUGCAndSEOUseRequestedGridPositions() {
        XCTAssertEqual(HubCategories.hubDisplayOrder.first?.id, "marketing")
        XCTAssertEqual(HubCategories.hubDisplayOrder[3].id, "ugc")
        XCTAssertEqual(HubCategories.hubDisplayOrder[14].id, "seo")
    }
}
