import SDMCore
import SwiftUI

struct MenuBarDownloadList: View {
    @Environment(\.openWindow) private var openWindow
    let service: DownloadService

    var body: some View {
        let snapshots = RecentDownloads.select(from: service.snapshots)

        VStack(alignment: .leading) {
            Text("Recent Downloads")
                .font(.headline)
                .padding([.top, .horizontal])

            if let initializationError = service.initializationError {
                ContentUnavailableView {
                    Label("Download Engine Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(initializationError)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.horizontal)
            } else if service.isLoadingHistory {
                ProgressView("Loading Downloads…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if snapshots.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "tray",
                    description: Text("Recent downloads will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.horizontal)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(snapshots.enumerated()),
                            id: \.element.id
                        ) { index, snapshot in
                            Button(action: { openInfo(for: snapshot.id) }) {
                                MenuBarDownloadRow(snapshot: snapshot)
                            }
                            .buttonStyle(.plain)

                            if index < snapshots.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 520)
            }
        }
        .padding(.bottom)
    }

    private func openInfo(for id: DownloadID) {
        NSApp.activate()
        openWindow(value: id)
    }
}
