import SDMCore
import SwiftUI

struct DownloadInfoView: View {
    let service: DownloadService
    let downloadID: DownloadID

    @State private var section: DownloadInfoSection = .overview
    @State private var presentedError: PresentedDownloadError?

    private var snapshot: DownloadSnapshot? {
        service.snapshots.first { $0.id == downloadID }
    }

    var body: some View {
        Group {
            if let snapshot {
                VStack(spacing: 0) {
                    DownloadInfoHeaderView(snapshot: snapshot)

                    Divider()

                    Picker("Download Information", selection: $section) {
                        ForEach(DownloadInfoSection.allCases) { section in
                            Label(section.rawValue, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding()

                    Group {
                        switch section {
                        case .overview:
                            DownloadOverviewView(
                                snapshot: snapshot,
                                fallbackDirectory: service.defaultDestinationDirectory
                            )
                        case .connections:
                            DownloadConnectionsView(snapshot: snapshot)
                        case .log:
                            DownloadLogView(entries: service.logs(for: downloadID))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    DownloadInfoActionsView(
                        snapshot: snapshot,
                        fallbackDirectory: service.defaultDestinationDirectory,
                        isBusy: service.commandInFlightIDs.contains(downloadID)
                    ) { command in
                        perform(command)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Download Not Available", systemImage: "questionmark.folder")
                } description: {
                    Text("This download was removed from history or is no longer available.")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
        .task(id: downloadID) {
            await service.refreshLogs(for: downloadID)
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func perform(_ command: DownloadCommand) {
        Task { @MainActor in
            do {
                try await service.perform(command, on: downloadID)
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not \(command.title)",
                    error: error
                )
            }
        }
    }
}
