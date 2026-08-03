import SDMCore
import SwiftUI

struct MenuBarDownloadRow: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.displayFilename)
                    .lineLimit(1)

                Spacer()

                Label(snapshot.state.title, systemImage: snapshot.state.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(snapshot.state.tint)
                    .lineLimit(1)
            }

            if let progress = snapshot.progressFraction {
                ProgressView(value: progress)
                    .accessibilityHidden(true)
            } else if snapshot.state.showsIndeterminateMenuBarProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            HStack {
                Text(transferredDescription)

                Spacer()

                Label(
                    DownloadFormatting.speed(snapshot.bytesPerSecond),
                    systemImage: "speedometer"
                )
                Label(
                    DownloadFormatting.duration(snapshot.estimatedTimeRemaining),
                    systemImage: "timer"
                )
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.displayFilename)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens download information")
    }

    private var transferredDescription: String {
        let downloaded = DownloadFormatting.bytes(snapshot.downloadedBytes)
        guard let contentLength = snapshot.contentLength else { return downloaded }
        return "\(downloaded) / \(DownloadFormatting.bytes(contentLength))"
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
