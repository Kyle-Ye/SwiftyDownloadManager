import SDMCore
import SwiftUI

struct DownloadInfoActionsView: View {
    let snapshot: DownloadSnapshot
    let fallbackDirectory: URL
    let isBusy: Bool
    let perform: (DownloadCommand) -> Void

    private var lifecycleCommands: [DownloadCommand] {
        snapshot.availableCommands.filter { $0 != .remove }
    }

    var body: some View {
        HStack {
            Button("Show in Finder", systemImage: "folder", action: showInFinder)

            Spacer()

            ForEach(lifecycleCommands) { command in
                Button(role: command.role) {
                    perform(command)
                } label: {
                    Label(command.title, systemImage: command.systemImage)
                }
                .disabled(isBusy)
            }
        }
        .padding()
    }

    private func showInFinder() {
        if let destinationURL = snapshot.destinationURL {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            } else {
                NSWorkspace.shared.open(destinationURL.deletingLastPathComponent())
            }
        } else {
            NSWorkspace.shared.open(fallbackDirectory)
        }
    }
}
