#if os(macOS)
import SwiftUI

struct ChromeExtensionCard: View {
    let chromeIsInstalled: Bool
    let webStoreURL: URL?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Label(
                    chromeIsInstalled ? "Google Chrome detected" : "Google Chrome not detected",
                    systemImage: chromeIsInstalled
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
                .foregroundStyle(chromeIsInstalled ? .green : .secondary)

                Divider()

                Label(
                    "Send supported HTTP and HTTPS download links to SDM.",
                    systemImage: "arrow.down.circle"
                )
                Label(
                    "Use Download with SDM from a link's context menu.",
                    systemImage: "contextualmenu.and.cursorarrow"
                )
                Label(
                    "Recognize direct file links and downloads opened after a click.",
                    systemImage: "link"
                )

                Text("Downloads that require browser-only cookies, request bodies, or custom headers are not yet supported.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let webStoreURL {
                    Link(destination: webStoreURL) {
                        Label("Add Chrome Extension", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Google Chrome", systemImage: "globe")
                .font(.headline)
        }
    }
}
#endif
