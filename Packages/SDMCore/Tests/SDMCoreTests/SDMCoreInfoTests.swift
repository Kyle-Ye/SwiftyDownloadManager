import XCTest
@testable import SDMCore

final class SDMCoreInfoTests: XCTestCase {
    func testEngineBridgeExposesVersion() {
        XCTAssertEqual(SDMCoreInfo.engineABIVersion, 1)
        XCTAssertEqual(SDMCoreInfo.engineVersion, "0.1.0-dev")
    }
}
