import XCTest
@testable import WelcomeKit

final class WelcomePaginationTests: XCTestCase {
    func testAdvancingCompletesOnlyAfterTheLastPage() {
        var pagination = WelcomePagination(pageCount: 3)
        XCTAssertFalse(pagination.canGoBack)
        XCTAssertFalse(pagination.advance())
        XCTAssertEqual(pagination.selectedIndex, 1)
        XCTAssertTrue(pagination.canGoBack)
        XCTAssertFalse(pagination.advance())
        XCTAssertEqual(pagination.selectedIndex, 2)
        XCTAssertTrue(pagination.isLastPage)
        XCTAssertTrue(pagination.advance())
        XCTAssertEqual(pagination.selectedIndex, 2)
    }

    func testGoingBackNeverMovesBeforeTheFirstPage() {
        var pagination = WelcomePagination(pageCount: 3)
        _ = pagination.advance()
        pagination.goBack()
        pagination.goBack()
        XCTAssertEqual(pagination.selectedIndex, 0)
        XCTAssertFalse(pagination.canGoBack)
        XCTAssertFalse(pagination.isLastPage)
    }

    func testSinglePageFinishesImmediatelyWithoutAdvancing() {
        var pagination = WelcomePagination(pageCount: 1)
        XCTAssertTrue(pagination.isLastPage)
        XCTAssertTrue(pagination.advance())
        XCTAssertEqual(pagination.selectedIndex, 0)
        XCTAssertFalse(pagination.canGoBack)
    }

    func testEmptyTourCanFinishAndBecomePopulated() {
        var pagination = WelcomePagination(pageCount: 0)
        XCTAssertTrue(pagination.advance())
        pagination.goBack()
        XCTAssertEqual(pagination.selectedIndex, 0)
        pagination.updatePageCount(2)
        XCTAssertFalse(pagination.isLastPage)
        XCTAssertFalse(pagination.advance())
        XCTAssertEqual(pagination.selectedIndex, 1)
    }

    func testRemovingPagesClampsSelectionAndHandlesAnEmptyReplacement() {
        var pagination = WelcomePagination(pageCount: 4)
        _ = pagination.advance()
        _ = pagination.advance()
        _ = pagination.advance()
        pagination.updatePageCount(2)
        XCTAssertEqual(pagination.selectedIndex, 1)
        XCTAssertTrue(pagination.isLastPage)
        pagination.updatePageCount(0)
        XCTAssertEqual(pagination.selectedIndex, 0)
        XCTAssertFalse(pagination.canGoBack)
        XCTAssertTrue(pagination.advance())
    }

    func testAppendingPagesPreservesTheCurrentSelection() {
        var pagination = WelcomePagination(pageCount: 2)
        _ = pagination.advance()
        pagination.updatePageCount(4)
        XCTAssertEqual(pagination.selectedIndex, 1)
        XCTAssertFalse(pagination.isLastPage)
    }
}
