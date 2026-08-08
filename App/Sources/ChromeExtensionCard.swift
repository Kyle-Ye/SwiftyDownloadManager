#if os(macOS)
import SwiftUI

struct ChromeExtensionCard: View {
    let applicationIcon: NSImage?
    let chromeIsInstalled: Bool
    let webStoreURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserExtensionDesign.cardSpacing) {
            HStack(alignment: .top, spacing: BrowserExtensionDesign.cardSpacing) {
                BrowserExtensionIcon(
                    applicationIcon: applicationIcon,
                    placeholderSystemImage: "questionmark.app.dashed"
                )

                HStack(spacing: BrowserExtensionDesign.inlineSpacing) {
                    Text("Google Chrome")
                        .font(.headline)

                    BrowserExtensionStatusBadge(
                        title: chromeIsInstalled ? "Chrome found" : "Chrome not found",
                        systemImage: chromeIsInstalled
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle.fill",
                        tint: chromeIsInstalled ? .green : .secondary
                    )
                }

                Spacer(minLength: BrowserExtensionDesign.inlineSpacing)

                if let webStoreURL {
                    Link(destination: webStoreURL) {
                        Label("Add Chrome Extension", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Opens the Chrome Web Store")
                }
            }

            Text("Capture direct download links without leaving the page you are browsing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(0)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, BrowserExtensionDesign.cardContentInset)

            VStack(alignment: .leading, spacing: BrowserExtensionDesign.featureSpacing) {
                BrowserFeatureRow(
                    title: "Send supported HTTP and HTTPS downloads to SDM",
                    systemImage: "arrow.down.circle.fill"
                )
                BrowserFeatureRow(
                    title: "Start a download from the link context menu",
                    systemImage: "cursorarrow.click.2"
                )
                BrowserFeatureRow(
                    title: "Recognize direct file links opened after a click",
                    systemImage: "link.circle.fill"
                )
            }

            Label(
                "Downloads that depend on browser-only cookies, request bodies, or custom headers are not supported yet.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
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
}
#endif
