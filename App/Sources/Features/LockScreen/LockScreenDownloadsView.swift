#if os(macOS)
import SwiftUI

struct LockScreenDownloadsView: View {
    @Bindable var service: DownloadService

    var body: some View {
        let snapshots = LockScreenDownloads.select(from: service.snapshots)
        let activeCount = service.snapshots.count {
            $0.state.appearsOnLockScreen
        }

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Swifty Download Manager")
                        .bold()
                    Text("^[\(activeCount) active download](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                    "No Active Downloads",
                    systemImage: "tray",
                    description: Text("New downloads will appear here while your Mac is locked.")
                )
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ForEach(snapshots) { snapshot in
                    LockScreenDownloadRow(snapshot: snapshot)

                    if snapshot.id != snapshots.last?.id {
                        Divider()
                    }
                }

                let hiddenCount = activeCount - snapshots.count
                if hiddenCount > 0 {
                    Text("^[\(hiddenCount) more active download](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
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
        service: .preview(snapshots: DownloadPreviewFixtures.snapshots)
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
    LockScreenDownloadsView(service: .preview())
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
