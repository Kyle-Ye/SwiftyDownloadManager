import SDMCore
import SwiftUI

struct DownloadLogRow: View {
    let entry: DownloadDiagnosticEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: entry.level.systemImage)
                .foregroundStyle(entry.level.tint)
                .accessibilityHidden(true)

            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(entry.message)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.level.title), \(entry.timestamp.formatted()), \(entry.message)"
        )
    }
}

#if DEBUG
#Preview("Download Log Rows") {
    List(DownloadPreviewFixtures.diagnosticEvents) { entry in
        DownloadLogRow(entry: entry)
    }
    .frame(minWidth: 640, minHeight: 220)
}
#endif
