import SwiftUI

struct DownloadLogRow: View {
    let entry: DownloadLogEntry

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
            "\(entry.level.rawValue), \(entry.timestamp.formatted()), \(entry.message)"
        )
    }
}

private extension DownloadLogLevel {
    var systemImage: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
