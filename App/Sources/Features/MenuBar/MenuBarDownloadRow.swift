import SDMCore
import SwiftUI

struct MenuBarDownloadRow: View {
    let snapshot: DownloadSnapshot
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.state.systemImage)
                .foregroundStyle(snapshot.state.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(snapshot.displayFilename)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(snapshot.state.title)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.state.tint)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    progressContent

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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .background(
            Color.primary.opacity(isHovered ? 0.07 : 0),
            in: .rect(cornerRadius: 6)
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.displayFilename)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens download information")
    }

    @ViewBuilder
    private var progressContent: some View {
        if let progress = snapshot.progressFraction {
            ProgressView(value: progress)
                .controlSize(.small)
                .frame(width: 92)
                .accessibilityHidden(true)

            Text(progress.formatted(.percent.precision(.fractionLength(0))))
        } else if snapshot.state.showsIndeterminateMenuBarProgress {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)

            Text(transferredDescription)
        } else {
            Text(transferredDescription)
        }
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
        let progress: String
        if let fraction = snapshot.progressFraction {
            progress = fraction.formatted(
                .percent.precision(.fractionLength(0))
            )
        } else {
            progress = transferredDescription
        }

        return [
            snapshot.state.title,
            progress,
            "Speed \(DownloadFormatting.speed(snapshot.bytesPerSecond))",
            "Remaining \(DownloadFormatting.duration(snapshot.estimatedTimeRemaining))",
        ].joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Menu Bar Download Rows") {
    VStack(spacing: 0) {
        ForEach(DownloadPreviewFixtures.snapshots) { snapshot in
            MenuBarDownloadRow(snapshot: snapshot)
        }
    }
    .frame(width: 360)
    .padding(.vertical, 6)
}
#endif
