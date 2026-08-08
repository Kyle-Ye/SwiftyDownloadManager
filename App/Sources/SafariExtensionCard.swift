#if os(macOS)
import SwiftUI

struct SafariExtensionCard: View {
    let isEnabled: Bool?
    let openSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Label(statusTitle, systemImage: statusSystemImage)
                    .foregroundStyle(statusStyle)

                Divider()

                Text("Enable the bundled extension in Safari and allow access to the websites where it should detect downloads.")
                    .foregroundStyle(.secondary)

                Button("Open Safari Extension Settings", action: openSettings)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Safari", systemImage: "safari")
                .font(.headline)
        }
    }

    private var statusTitle: String {
        switch isEnabled {
        case true: "Extension enabled"
        case false: "Extension disabled"
        case nil: "Checking extension status…"
        }
    }

    private var statusSystemImage: String {
        switch isEnabled {
        case true: "checkmark.circle.fill"
        case false: "exclamationmark.circle"
        case nil: "ellipsis.circle"
        }
    }

    private var statusStyle: Color {
        isEnabled == true ? .green : .secondary
    }
}
#endif
