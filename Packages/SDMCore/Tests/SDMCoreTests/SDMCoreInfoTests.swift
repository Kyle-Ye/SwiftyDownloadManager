import XCTest
@testable import SDMCore

final class SDMCoreInfoTests: XCTestCase {
    func testEngineBridgeExposesVersion() {
        XCTAssertEqual(SDMCoreInfo.engineABIVersion, 2)
        XCTAssertEqual(SDMCoreInfo.engineVersion, "0.2.0-dev")
    }
}
