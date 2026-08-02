import Foundation
import SDMCore
import XCTest
@testable import SDMApp

final class SDMAppTests: XCTestCase {
    func testInitialDownloadFiltersRemainStable() {
        XCTAssertEqual(DownloadFilter.allCases.count, 5)
        XCTAssertEqual(DownloadFilter.allCases.first, .all)
    }

    func testAppCanFormAnSDMCoreDownloadRequest() throws {
        let request = DownloadRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/archive.zip")),
            destinationDirectory: FileManager.default.temporaryDirectory,
            connectionLimit: 8
        )

        XCTAssertEqual(request.connectionLimit, 8)
    }
}
