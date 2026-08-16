#if os(macOS)
import SDMCore
import SwiftUI

struct LockScreenDownloadRow: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snapshot.state.systemImage)
                .font(.title3)
                .foregroundStyle(snapshot.state.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.displayFilename)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(snapshot.state.title)
                        .foregroundStyle(snapshot.state.tint)
                        .lineLimit(1)
                }

                if let progress = snapshot.progressFraction {
                    LockScreenProgressBar(
                        progress: progress,
                        tint: snapshot.state.tint
                    )
                        .accessibilityHidden(true)
                } else if snapshot.state.showsIndeterminateMenuBarProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(snapshot.state.tint)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 8) {
                    Text(transferredDescription)

                    Spacer(minLength: 8)

                    if let liveMetricsDescription {
                        Text(liveMetricsDescription)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.displayFilename)
        .accessibilityValue(accessibilityValue)
    }

    private var transferredDescription: String {
        let downloaded = DownloadFormatting.bytes(snapshot.downloadedBytes)
        guard let contentLength = snapshot.contentLength else { return downloaded }
        return "\(downloaded) / \(DownloadFormatting.bytes(contentLength))"
    }

    private var liveMetricsDescription: String? {
        var metrics: [String] = []
        if snapshot.bytesPerSecond > 0 {
            metrics.append(DownloadFormatting.speed(snapshot.bytesPerSecond))
        }
        if snapshot.estimatedTimeRemaining != nil {
            metrics.append(
                "\(DownloadFormatting.duration(snapshot.estimatedTimeRemaining)) left"
            )
        }
        return metrics.isEmpty ? nil : metrics.joined(separator: " · ")
    }

    private var accessibilityValue: String {
        let progress = snapshot.progressFraction?.formatted(
            .percent.precision(.fractionLength(0))
        ) ?? transferredDescription
        return [
            snapshot.state.title,
            progress,
            "Speed \(DownloadFormatting.speed(snapshot.bytesPerSecond))",
            "Remaining \(DownloadFormatting.duration(snapshot.estimatedTimeRemaining))",
        ].joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Lock Screen Download") {
    LockScreenDownloadRow(snapshot: DownloadPreviewFixtures.snapshots[1])
        .frame(width: 400)
        .padding()
}
#endif
#endif
