import XCTest
@testable import SDMCore

final class SDMCoreInfoTests: XCTestCase {
    func testEngineBridgeExposesVersion() {
        XCTAssertEqual(SDMCoreInfo.engineABIVersion, 4)
        XCTAssertEqual(SDMCoreInfo.engineVersion, "0.6.0")
        XCTAssertTrue(SDMCoreInfo.libcurlVersion.contains("libcurl/8.21.0"))
    }
}
