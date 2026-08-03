import SDMCore
import SwiftUI

struct MenuBarDownloadList: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var service: DownloadService

    var body: some View {
        let snapshots = RecentDownloads.select(from: service.snapshots)

        VStack(spacing: 0) {
            HStack {
                Text("Swifty Download Manager")
                    .lineLimit(1)

                Spacer()

                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)

            Divider()
                .padding(.horizontal, 12)

            if let initializationError = service.initializationError {
                ContentUnavailableView {
                    Label(
                        "Download Engine Unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(initializationError)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .padding(.horizontal)
            } else if service.isLoadingHistory {
                ProgressView("Loading Downloads…")
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else if snapshots.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "tray",
                    description: Text("Recent downloads will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 110)
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
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
                                .padding(.leading, 44)
                                .padding(.trailing, 12)
                        }
                    }
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
    }

    private func openInfo(for id: DownloadID) {
        NSApp.activate()
        openWindow(value: id)
    }
}
