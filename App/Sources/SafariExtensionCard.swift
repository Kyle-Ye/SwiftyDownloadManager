#if os(macOS)
import SwiftUI

struct SafariExtensionCard: View {
    let applicationIcon: NSImage?
    let isEnabled: Bool?
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserExtensionDesign.cardSpacing) {
            HStack(alignment: .top, spacing: BrowserExtensionDesign.cardSpacing) {
                BrowserExtensionIcon(
                    applicationIcon: applicationIcon,
                    placeholderSystemImage: "safari"
                )

                HStack(spacing: BrowserExtensionDesign.inlineSpacing) {
                    Text("Safari")
                        .font(.headline)

                    BrowserExtensionStatusBadge(
                        title: statusTitle,
                        systemImage: statusSystemImage,
                        tint: statusStyle,
                        showsProgress: isEnabled == nil
                    )
                }

                Spacer(minLength: BrowserExtensionDesign.inlineSpacing)

                Button(
                    "Open Safari Extension Settings",
                    systemImage: "gear",
                    action: openSettings
                )
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens Safari extension settings")
            }

            Text("Use the extension already bundled with Swifty Download Manager.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(0)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, BrowserExtensionDesign.cardContentInset)

            HStack(spacing: BrowserExtensionDesign.wideSpacing) {
                BrowserFeatureRow(
                    title: "Turn on the SDM extension",
                    systemImage: "checkmark.circle.fill"
                )
                BrowserFeatureRow(
                    title: "Allow access to download websites",
                    systemImage: "hand.raised.circle.fill"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrowserExtensionDesign.cardPadding)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: .rect(cornerRadius: BrowserExtensionDesign.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: BrowserExtensionDesign.cardRadius)
                .stroke(.quaternary)
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
        case false: "exclamationmark.circle.fill"
        case nil: "ellipsis.circle"
        }
    }

    private var statusStyle: Color {
        switch isEnabled {
        case true: .green
        case false: .orange
        case nil: .secondary
        }
    }
}
#endif
