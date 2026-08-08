#if os(macOS)
import SDMCore
import SwiftUI

struct DownloadSelectionToolbar: View, Equatable {
    let selectedDownloadIDs: Set<DownloadID>
    let commands: [DownloadCommand]
    let isBusy: Bool
    let showInfo: (DownloadID) -> Void
    let perform: (DownloadCommand, Set<DownloadID>) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedDownloadIDs == rhs.selectedDownloadIDs
            && lhs.commands == rhs.commands
            && lhs.isBusy == rhs.isBusy
    }

    private var selectedDownloadID: DownloadID? {
        guard selectedDownloadIDs.count == 1 else { return nil }
        return selectedDownloadIDs.first
    }

    var body: some View {
        HStack {
            if let selectedDownloadID {
                Button("Info", systemImage: "info.circle") {
                    showInfo(selectedDownloadID)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            ForEach(commands) { command in
                Button(role: command.role) {
                    perform(command, selectedDownloadIDs)
                } label: {
                    Label(
                        command.title(forSelectionCount: selectedDownloadIDs.count),
                        systemImage: command.systemImage
                    )
                }
                .disabled(isBusy)
            }
        }
        .frame(minWidth: 1, minHeight: 1)
    }
}
#endif
