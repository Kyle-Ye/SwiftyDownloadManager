/// Keeps navigation valid when a host changes the number of pages during a tour.
struct WelcomePagination: Equatable {
    private(set) var pageCount: Int
    private(set) var selectedIndex = 0

    init(pageCount: Int) {
        self.pageCount = max(0, pageCount)
    }

    var canGoBack: Bool { selectedIndex > 0 }
    var isLastPage: Bool { selectedIndex >= pageCount - 1 }

    mutating func updatePageCount(_ count: Int) {
        pageCount = max(0, count)
        selectedIndex = min(selectedIndex, max(0, pageCount - 1))
    }

    mutating func goBack() {
        selectedIndex = max(0, selectedIndex - 1)
    }

    /// Returns true when advancing should complete the tour, including an empty tour.
    mutating func advance() -> Bool {
        guard !isLastPage else { return true }
        selectedIndex += 1
        return false
    }
}
