#if os(macOS)
import SwiftUI

struct BrowserCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button(
                "Browser Extensions…",
                systemImage: "globe",
                action: showBrowserExtensions
            )
        }
    }

    private func showBrowserExtensions() {
        openWindow(id: AppWindowID.browsers)
    }
}
#endif
