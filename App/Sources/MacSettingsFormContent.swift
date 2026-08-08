#if os(macOS)
import SDMCore
import SwiftUI

struct MacSettingsFormContent: View {
    @Binding var defaultConnectionCount: Int
    @Binding var showsMenuBarIcon: Bool
    @Binding var selectedEngine: String
    let engineDescriptors: [DownloadEngineDescriptor]
    let selectedDescriptor: DownloadEngineDescriptor?
    let safariExtensionIsEnabled: Bool?
    let databaseURL: URL?
    let openSafariSettings: () -> Void
    let showBrowserExtensions: () -> Void
    let showLegalNotices: () -> Void

    var body: some View {
        Section("General") {
            Picker("Application icon location", selection: $showsMenuBarIcon) {
                Text("In Dock and Menu Bar")
                    .tag(true)
                Text("In Dock only")
                    .tag(false)
            }
            .pickerStyle(.menu)

            Picker("Download engine", selection: $selectedEngine) {
                ForEach(engineDescriptors) { descriptor in
                    Text(descriptor.kind.title)
                        .tag(descriptor.kind.rawValue)
                }
            }
            .pickerStyle(.menu)

            if let selectedDescriptor {
                ForEach(DownloadFeature.allCases) { feature in
                    Label(
                        feature.title,
                        systemImage: selectedDescriptor.supports(feature)
                            ? "checkmark.circle.fill"
                            : "xmark.circle"
                    )
                    .foregroundStyle(
                        selectedDescriptor.supports(feature) ? .primary : .secondary
                    )
                }
            }
        }

        Section {
            Stepper(
                "Default connections: \(defaultConnectionCount)",
                value: $defaultConnectionCount,
                in: 1 ... 16
            )
            .disabled(selectedDescriptor?.supports(.multiConnectionTransfers) == false)
        } header: {
            Text("Downloads")
        } footer: {
            if selectedDescriptor?.supports(.multiConnectionTransfers) == false {
                Text("URLSession manages connections internally and uses one connection per download.")
            }
        }

        Section("Browser Extensions") {
            LabeledContent("Safari") {
                Text(extensionStatusTitle)
                    .foregroundStyle(extensionStatusStyle)
            }

            Text("Enable the extension in Safari, then allow website access. Download links and the Download with SDM context menu will send supported HTTP and HTTPS files to SDM.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Open Safari Extension Settings", action: openSafariSettings)
            Button("Manage Browser Extensions", action: showBrowserExtensions)
        }

        Section("Engine") {
            LabeledContent("Version", value: SDMCoreInfo.engineVersion)
            LabeledContent("libcurl", value: SDMCoreInfo.libcurlVersion)
            LabeledContent("ABI") {
                Text(SDMCoreInfo.engineABIVersion, format: .number)
            }
            if let databaseURL {
                LabeledContent("History database") {
                    Text(databaseURL.path(percentEncoded: false))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }

        Section("Legal") {
            Text("libcurl, curl-apple, OpenSSL, and Mozilla license texts are included with the app.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("View Third-Party Licenses", action: showLegalNotices)
        }
    }

    private var extensionStatusTitle: String {
        switch safariExtensionIsEnabled {
        case true: "Enabled"
        case false: "Disabled"
        case nil: "Checking…"
        }
    }

    private var extensionStatusStyle: Color {
        safariExtensionIsEnabled == true ? .green : .secondary
    }
}
#endif
