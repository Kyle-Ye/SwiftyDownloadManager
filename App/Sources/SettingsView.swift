import SDMCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultConnectionCount") private var defaultConnectionCount = 8

    var body: some View {
        Form {
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
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 260)
    }
}

#Preview {
    SettingsView()
}
