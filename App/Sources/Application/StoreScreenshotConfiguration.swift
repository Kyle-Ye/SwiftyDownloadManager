#if DEBUG && os(macOS)
import SwiftUI

struct StoreScreenshotConfiguration {
    static let modeArgument = "-StoreScreenshots"
    static let appearanceEnvironmentKey = "SDM_STORE_SCREENSHOT_APPEARANCE"
    static let windowSize = CGSize(width: 1_280, height: 640)

    let isEnabled: Bool
    let colorScheme: ColorScheme?
    let windowSize: CGSize?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        isEnabled = arguments.contains(Self.modeArgument)
        guard isEnabled else {
            colorScheme = nil
            windowSize = nil
            return
        }

        colorScheme = environment[Self.appearanceEnvironmentKey]?.lowercased() == "dark"
            ? .dark
            : .light
        windowSize = Self.windowSize
    }
}
#endif
