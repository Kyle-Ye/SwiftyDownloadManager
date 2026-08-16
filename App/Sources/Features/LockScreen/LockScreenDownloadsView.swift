#if os(macOS)
import SwiftUI

struct LockScreenDownloadsView: View {
    @AppStorage(AppStorageKey.lockScreenRecentDownloadLimit)
    private var recentDownloadLimit = RecentDownloads.defaultMaximumCount
    @Bindable var service: DownloadService
    let screenSize: CGSize

    var body: some View {
        let visibleDownloadLimit = LockScreenCardLayout.visibleDownloadLimit(
            requestedLimit: recentDownloadLimit,
            screenSize: screenSize
        )
        let snapshots = LockScreenDownloads.select(
            from: service.snapshots,
            limit: visibleDownloadLimit
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swifty Download Manager")
                        .bold()
                    Text("^[\(snapshots.count) recent download](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image("SDMLockScreenColorLogo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }

            Divider()

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
            } else if service.isLoadingHistory {
                ProgressView("Loading Downloads…")
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else if snapshots.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "tray",
                    description: Text(
                        "Recent downloads will appear here while your Mac is locked."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(snapshots.enumerated()),
                        id: \.element.id
                    ) { index, snapshot in
                        LockScreenDownloadRow(snapshot: snapshot)
                            .padding(.vertical, 8)

                        if index < snapshots.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: LockScreenCardLayout.width(for: screenSize))
        .frame(maxHeight: LockScreenCardLayout.maximumHeight(for: screenSize))
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .padding(40)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Lock Screen Downloads") {
    LockScreenDownloadsView(
        service: .preview(snapshots: DownloadPreviewFixtures.snapshots),
        screenSize: CGSize(width: 1_280, height: 720)
    )
    .frame(width: 1_280, height: 720)
    .background(
        LinearGradient(
            colors: [.indigo, .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#Preview("Lock Screen Empty State") {
    LockScreenDownloadsView(
        service: .preview(),
        screenSize: CGSize(width: 1_280, height: 720)
    )
    .frame(width: 1_280, height: 720)
    .background(
        LinearGradient(
            colors: [.blue, .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
#endif
#endif
