struct HubTaskBrowseState: Equatable {
    enum Page: Equatable {
        case categories
        case results(categoryIds: Set<String>)
    }

    private(set) var page: Page = .categories

    var isShowingResults: Bool {
        if case .results = page { return true }
        return false
    }

    var selectedCategoryIds: Set<String> {
        guard case let .results(categoryIds) = page else { return [] }
        return categoryIds
    }

    mutating func showAllResults() {
        page = .results(categoryIds: [])
    }

    mutating func showResults(for categoryId: String) {
        page = .results(categoryIds: [categoryId])
    }

    mutating func showPersonalizedResults(for categoryIds: Set<String>) {
        guard !categoryIds.isEmpty else { return }
        page = .results(categoryIds: categoryIds)
    }

    mutating func toggleResults(for categoryId: String) {
        var categoryIds = selectedCategoryIds
        if categoryIds.contains(categoryId) {
            categoryIds.remove(categoryId)
        } else {
            categoryIds.insert(categoryId)
        }
        page = .results(categoryIds: categoryIds)
    }

    func includes(categoryId: String) -> Bool {
        selectedCategoryIds.isEmpty || selectedCategoryIds.contains(categoryId)
    }

    mutating func showCategories() {
        page = .categories
    }
}
