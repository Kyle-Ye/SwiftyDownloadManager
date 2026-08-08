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
            #if os(macOS)
            Button("Show in Finder", systemImage: "folder", action: showInFinder)
            #else
            ShareLink(item: shareURL) {
                Label("Share File", systemImage: "square.and.arrow.up")
            }
            #endif

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

    #if os(macOS)
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
    #else
    private var shareURL: URL {
        snapshot.destinationURL ?? fallbackDirectory
    }
    #endif
}
