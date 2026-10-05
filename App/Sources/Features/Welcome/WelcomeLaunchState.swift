import Foundation

/// App-owned, installation-wide policy. The reusable tour does not store user defaults.
@MainActor
final class WelcomeLaunchState {
    private let defaults: UserDefaults
    private let suppressesPresentation: Bool
    private var hasClaimedPresentation = false

    init(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isRunningTests: Bool = NSClassFromString("XCTestCase") != nil
    ) {
        self.defaults = defaults
        suppressesPresentation = isRunningTests
            || arguments.contains("-StoreScreenshots")
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    /// Claim synchronously so multiple scenes cannot schedule the same first-launch tour.
    func claimAutomaticPresentation() -> Bool {
        guard !suppressesPresentation,
              !hasClaimedPresentation,
              !defaults.bool(forKey: AppStorageKey.hasPresentedWelcome) else {
            return false
        }
        hasClaimedPresentation = true
        return true
    }

    /// Called when the tour appears, so closing or skipping it still counts as seen.
    func recordPresentation() {
        guard !suppressesPresentation else { return }
        defaults.set(true, forKey: AppStorageKey.hasPresentedWelcome)
    }
}
