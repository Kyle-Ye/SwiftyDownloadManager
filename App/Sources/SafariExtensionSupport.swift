import SafariServices

enum SafariExtensionSupport {
    static let bundleIdentifier = "top.kyleye.swifty-download-manager-app.safari-extension"

    nonisolated static func isEnabled() async -> Bool? {
        await withCheckedContinuation { continuation in
            // The SDK marks this completion as UI-actor-isolated, but SafariServices
            // invokes it on an XPC queue. Keep the closure itself nonisolated and send
            // only the value across the continuation boundary.
            let completion: @Sendable (SFSafariExtensionState?, Error?) -> Void = { state, _ in
                continuation.resume(returning: state?.isEnabled)
            }
            SFSafariExtensionManager.getStateOfSafariExtension(
                withIdentifier: bundleIdentifier,
                completionHandler: completion
            )
        }
    }

    static func showPreferences() {
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: bundleIdentifier,
            completionHandler: nil
        )
    }
}
