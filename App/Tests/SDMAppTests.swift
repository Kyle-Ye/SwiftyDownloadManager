import XCTest
@testable import SDMApp

final class SDMAppTests: XCTestCase {
    func testInitialDownloadFiltersRemainStable() {
        XCTAssertEqual(DownloadFilter.allCases.count, 5)
        XCTAssertEqual(DownloadFilter.allCases.first, .all)
    }
}
