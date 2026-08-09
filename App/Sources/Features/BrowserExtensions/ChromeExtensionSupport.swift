#if os(macOS)
import SwiftUI

enum ChromeExtensionSupport {
    static let webStoreURL = URL(
        string: "https://chromewebstore.google.com/detail/jjhjgmnpneldikhkejhoeonjpbbekbpg"
    )

    private static let applicationBundleIdentifiers = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
    ]

    @MainActor
    static func isChromeInstalled() -> Bool {
        BrowserApplicationIconSupport.applicationURL(
            forBundleIdentifiers: applicationBundleIdentifiers
        ) != nil
    }

    @MainActor
    static func applicationIcon() -> NSImage? {
        BrowserApplicationIconSupport.icon(
            forBundleIdentifiers: applicationBundleIdentifiers
        )
    }
}
#endif
