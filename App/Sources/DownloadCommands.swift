import SwiftUI

struct DownloadCommands: Commands {
    @FocusedValue(\.newURLAction) private var newURLAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New URL", systemImage: "link.badge.plus", action: presentNewURL)
                .keyboardShortcut("u", modifiers: .command)
                .disabled(newURLAction == nil)
        }
    }

    private func presentNewURL() {
        newURLAction?()
    }
}
