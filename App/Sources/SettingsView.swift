import SDMCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
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
        .frame(width: 560, height: 360)
    }
}

#Preview {
    SettingsView(databaseURL: nil)
}
