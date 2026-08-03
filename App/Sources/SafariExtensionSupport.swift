import SafariServices

enum SafariExtensionSupport {
    static let bundleIdentifier = "top.kyleye.swifty-download-manager-app.safari-extension"

    static func showPreferences() {
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: bundleIdentifier,
            completionHandler: nil
        )
    }
}
