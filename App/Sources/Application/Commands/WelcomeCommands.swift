#if os(macOS)
import SwiftUI

struct WelcomeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let controller: SDMWelcomeController

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Welcome to Swifty Download Manager…", action: showWelcome)
        }
    }

    private func showWelcome() {
        controller.present {
            openWindow(id: AppWindowID.main)
        }
    }
}
#endif
