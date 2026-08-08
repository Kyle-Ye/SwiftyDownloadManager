import SafariServices
#if os(iOS)
import UIKit
#endif

enum SafariExtensionSupport {
    static let bundleIdentifier = "top.kyleye.swifty-download-manager-app.safari-extension"

    #if os(macOS)
    private static let applicationBundleIdentifiers = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    @MainActor
    static func applicationIcon() -> NSImage? {
        BrowserApplicationIconSupport.icon(
            forBundleIdentifiers: applicationBundleIdentifiers
        )
    }
    #endif

    nonisolated static func isEnabled() async -> Bool? {
        #if os(macOS)
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
        #else
        if #available(iOS 26.2, *) {
            return try? await SFSafariExtensionManager.stateOfExtension(
                withIdentifier: bundleIdentifier
            ).isEnabled
        }
        return nil
        #endif
    }

    @MainActor
    static func showPreferences() {
        #if os(macOS)
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: bundleIdentifier,
            completionHandler: nil
        )
        #else
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
