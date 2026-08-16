#if os(iOS)
import SDMCore
import SwiftUI

struct MobileDownloadRow: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: snapshot.state.systemImage)
                    .foregroundStyle(snapshot.state.tint)
                    .accessibilityHidden(true)

                Text(snapshot.displayFilename)
                    .lineLimit(1)

                Spacer()

                Text(snapshot.state.title)
                    .foregroundStyle(snapshot.state.tint)
            }

            if let progress = snapshot.progressFraction {
                ProgressView(value: progress)
                    .tint(snapshot.state.tint)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue(progress.formatted(.percent))
            }

            HStack {
                Text(snapshot.engine.title)
                Spacer()
                Text(DownloadFormatting.speed(snapshot.bytesPerSecond))
                Text(DownloadFormatting.duration(snapshot.estimatedTimeRemaining))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview("Download Rows") {
    List(DownloadPreviewFixtures.snapshots) { snapshot in
        MobileDownloadRow(snapshot: snapshot)
    }
}
#endif
#endif
