struct HubTaskBrowseState: Equatable {
    enum Page: Equatable {
        case categories
        case results(categoryId: String?)
    }

    private(set) var page: Page = .categories

    var isShowingResults: Bool {
        if case .results = page { return true }
        return false
    }

    var selectedCategoryId: String? {
        guard case let .results(categoryId) = page else { return nil }
        return categoryId
    }

    mutating func showAllResults() {
        page = .results(categoryId: nil)
    }

    mutating func showResults(for categoryId: String) {
        page = .results(categoryId: categoryId)
    }

    mutating func showCategories() {
        page = .categories
    }
}
