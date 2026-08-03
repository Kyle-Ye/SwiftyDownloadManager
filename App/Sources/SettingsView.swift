import SDMCore
import SafariServices
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @State private var safariExtensionIsEnabled: Bool?
    let databaseURL: URL?

    var body: some View {
        Form {
            Section("General") {
                Picker("Application icon location", selection: $showsMenuBarIcon) {
                    Text("In Dock and Menu Bar")
                        .tag(true)
                    Text("In Dock only")
                        .tag(false)
                }
                .pickerStyle(.menu)
            }

            Section("Downloads") {
                Stepper(
                    "Default connections: \(defaultConnectionCount)",
                    value: $defaultConnectionCount,
                    in: 1 ... 16
                )
            }

            Section("Safari Extension") {
                LabeledContent("Status") {
                    Text(extensionStatusTitle)
                        .foregroundStyle(extensionStatusColor)
                }

                Text("Enable the extension in Safari, then allow website access. Download links and the Download with SDM context menu will send supported HTTP and HTTPS files to SDM.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open Safari Extension Settings") {
                    SafariExtensionSupport.showPreferences()
                }
            }

            Section("Engine") {
                LabeledContent("Version", value: SDMCoreInfo.engineVersion)
                LabeledContent("ABI", value: String(SDMCoreInfo.engineABIVersion))
                if let databaseURL {
                    LabeledContent("History database") {
                        Text(databaseURL.path(percentEncoded: false))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 470)
        .task {
            refreshSafariExtensionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSafariExtensionState()
        }
    }

    private var extensionStatusTitle: String {
        switch safariExtensionIsEnabled {
        case true: "Enabled"
        case false: "Disabled"
        case nil: "Checking…"
        }
    }

    private var extensionStatusColor: Color {
        switch safariExtensionIsEnabled {
        case true: .green
        case false: .secondary
        case nil: .secondary
        }
    }

    private func refreshSafariExtensionState() {
        SFSafariExtensionManager.getStateOfSafariExtension(
            withIdentifier: SafariExtensionSupport.bundleIdentifier
        ) { state, _ in
            safariExtensionIsEnabled = state?.isEnabled
        }
    }
}

#Preview {
    SettingsView(databaseURL: nil)
}
