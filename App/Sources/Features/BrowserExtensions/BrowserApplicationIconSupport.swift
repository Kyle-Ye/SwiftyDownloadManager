#if os(macOS)
import AppKit

enum BrowserApplicationIconSupport {
    @MainActor
    static func applicationURL(forBundleIdentifiers bundleIdentifiers: [String]) -> URL? {
        bundleIdentifiers.lazy.compactMap { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        }.first
    }

    @MainActor
    static func icon(forBundleIdentifiers bundleIdentifiers: [String]) -> NSImage? {
        guard let applicationURL = applicationURL(
            forBundleIdentifiers: bundleIdentifiers
        ) else {
            return nil
        }

        return NSWorkspace.shared.icon(
            forFile: applicationURL.path(percentEncoded: false)
        )
    }
}
#endif
