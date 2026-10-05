import Foundation
import WelcomeKit

@MainActor
enum SDMWelcomeContent {
    static var pages: [WelcomePage] {
        [
            WelcomePage(
                id: SDMWelcomePageID.welcome.rawValue,
                title: "Welcome to Swifty Download Manager",
                message: "Keep your downloads in one place. Add a file link, follow its progress, and find it again in your download history."
            ),
            WelcomePage(
                id: SDMWelcomePageID.connections.rawValue,
                title: "Downloads at your pace",
                message: "Pause and resume supported downloads. Use parallel connections when your download engine and the server support them."
            ),
            WelcomePage(
                id: SDMWelcomePageID.browsers.rawValue,
                title: "From browser to download",
                message: browserMessage
            ),
        ]
    }

    private static var browserMessage: LocalizedStringResource {
        #if os(macOS)
        "Send supported file links from Safari or Chrome to SDM. Open Browser Extensions to set up your extensions."
        #else
        "Send supported file links from Safari to SDM. Enable the included Safari extension in Settings to get started."
        #endif
    }
}
