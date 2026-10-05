import Foundation
import XCTest
@testable import SDMApp

final class WelcomeLaunchStateTests: XCTestCase {
    @MainActor
    func testOnlyOneSceneCanClaimTheAutomaticPresentation() throws {
        try withIsolatedDefaults { defaults, _ in
            let state = makeState(defaults: defaults)

            XCTAssertTrue(state.claimAutomaticPresentation())
            XCTAssertFalse(state.claimAutomaticPresentation())
            XCTAssertFalse(state.claimAutomaticPresentation())
        }
    }

    @MainActor
    func testUnpresentedClaimCanBeRetriedAfterRelaunch() throws {
        try withIsolatedDefaults { defaults, _ in
            let interruptedLaunch = makeState(defaults: defaults)
            XCTAssertTrue(interruptedLaunch.claimAutomaticPresentation())
            XCTAssertNil(defaults.object(forKey: AppStorageKey.hasPresentedWelcome))

            let nextLaunch = makeState(defaults: defaults)
            XCTAssertTrue(nextLaunch.claimAutomaticPresentation())
        }
    }

    @MainActor
    func testPresentedWelcomeIsRememberedAcrossStateAndDefaultsInstances() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let firstLaunch = makeState(defaults: defaults)
            XCTAssertTrue(firstLaunch.claimAutomaticPresentation())
            firstLaunch.recordPresentation()

            let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            XCTAssertTrue(reloadedDefaults.bool(forKey: AppStorageKey.hasPresentedWelcome))
            let nextLaunch = makeState(defaults: reloadedDefaults)
            XCTAssertFalse(nextLaunch.claimAutomaticPresentation())
        }
    }

    @MainActor
    func testManualPresentationAlsoCompletesTheFirstLaunchWelcome() throws {
        try withIsolatedDefaults { defaults, _ in
            let state = makeState(defaults: defaults)

            state.recordPresentation()

            XCTAssertTrue(defaults.bool(forKey: AppStorageKey.hasPresentedWelcome))
            XCTAssertFalse(state.claimAutomaticPresentation())
            XCTAssertFalse(makeState(defaults: defaults).claimAutomaticPresentation())
        }
    }

    @MainActor
    func testSuppressedLaunchesLeaveWelcomeAvailableForTheNextNormalLaunch() throws {
        let configurations: [(arguments: [String], environment: [String: String], isRunningTests: Bool)] = [
            (["SDMApp", "-StoreScreenshots"], [:], false),
            ([], ["XCODE_RUNNING_FOR_PREVIEWS": "1"], false),
            ([], ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"], false),
            ([], ["XCTestBundlePath": "/tmp/SDMAppTests.xctest"], false),
            ([], ["XCTestSessionIdentifier": UUID().uuidString], false),
            ([], [:], true),
        ]

        for configuration in configurations {
            try withIsolatedDefaults { defaults, _ in
                let state = WelcomeLaunchState(
                    defaults: defaults,
                    arguments: configuration.arguments,
                    environment: configuration.environment,
                    isRunningTests: configuration.isRunningTests
                )

                XCTAssertFalse(state.claimAutomaticPresentation())
                state.recordPresentation()
                XCTAssertFalse(state.claimAutomaticPresentation())
                XCTAssertNil(defaults.object(forKey: AppStorageKey.hasPresentedWelcome))
                XCTAssertTrue(makeState(defaults: defaults).claimAutomaticPresentation())
            }
        }
    }

    @MainActor
    private func makeState(defaults: UserDefaults) -> WelcomeLaunchState {
        WelcomeLaunchState(
            defaults: defaults,
            arguments: [],
            environment: [:],
            isRunningTests: false
        )
    }

    @MainActor
    private func withIsolatedDefaults(
        _ body: @MainActor (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "WelcomeLaunchStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }
}
