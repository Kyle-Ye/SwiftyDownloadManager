#if os(macOS)
import SwiftUI

enum ChromeExtensionSupport {
    static let webStoreURL = URL(
        string: "https://chromewebstore.google.com/search/Swifty%20Download%20Manager"
    )

    private static let chromeBundleIdentifiers = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
    ]

    @MainActor
    static func isChromeInstalled() -> Bool {
        chromeBundleIdentifiers.contains { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) != nil
        }
    }
}
#endif
