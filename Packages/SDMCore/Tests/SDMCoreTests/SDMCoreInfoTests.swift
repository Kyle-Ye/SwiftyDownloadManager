import XCTest
@testable import SDMCore

final class SDMCoreInfoTests: XCTestCase {
    func testEngineBridgeExposesVersion() {
        XCTAssertEqual(SDMCoreInfo.engineABIVersion, 3)
        XCTAssertEqual(SDMCoreInfo.engineVersion, "0.3.0-dev")
        XCTAssertTrue(SDMCoreInfo.libcurlVersion.contains("libcurl/8.21.0"))
    }
}
