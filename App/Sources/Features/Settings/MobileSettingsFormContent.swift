#if os(iOS)
import SDMCore
import SwiftUI

struct MobileSettingsFormContent: View {
    @Binding var defaultConnectionCount: Int
    @Binding var defaultDownloadLocation: DefaultDownloadLocation
    @Binding var selectedEngine: String
    let engineDescriptors: [DownloadEngineDescriptor]
    let selectedDescriptor: DownloadEngineDescriptor?
    let safariExtensionIsEnabled: Bool?
    let databaseURL: URL?
    let defaultDestinationDirectory: URL
    let chooseCustomDefaultDestination: () -> Void
    let openSafariSettings: () -> Void

    var body: some View {
        Section("General") {
            Picker("Download engine", selection: $selectedEngine) {
                ForEach(engineDescriptors) { descriptor in
                    Text(descriptor.kind.title)
                        .tag(descriptor.kind.rawValue)
                }
            }
            .pickerStyle(.navigationLink)

            if let selectedDescriptor {
                NavigationLink {
                    DownloadEngineFeaturesView(descriptor: selectedDescriptor)
                } label: {
                    Label("Engine Capabilities", systemImage: "gearshape.2")
                }
            }
        }

        Section {
            Picker("Default save location", selection: $defaultDownloadLocation) {
                ForEach(DefaultDownloadLocation.availableLocations) { location in
                    Text(location.title)
                        .tag(location)
                }
            }
            .pickerStyle(.navigationLink)

            LabeledContent("Current folder") {
                Text(currentFolderName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if defaultDownloadLocation == .custom {
                Button(
                    "Choose External Folder…",
                    systemImage: "folder",
                    action: chooseCustomDefaultDestination
                )
            }

            Stepper(value: $defaultConnectionCount, in: 1 ... 16) {
                LabeledContent("Default connections") {
                    Text(defaultConnectionCount, format: .number)
                }
            }
            .disabled(selectedDescriptor?.supports(.multiConnectionTransfers) == false)
        } header: {
            Text("Downloads")
        } footer: {
            VStack(alignment: .leading) {
                Text("Choose any folder available in Files, including iCloud Drive and supported third-party providers.")
                if selectedDescriptor?.supports(.multiConnectionTransfers) == false {
                    Text("URLSession manages connections internally and uses one connection per download.")
                } else {
                    Text("New downloads use this many connections when the server supports segmented transfers.")
                }
            }
        }

        Section {
            LabeledContent("Status") {
                Text(extensionStatusTitle)
                    .foregroundStyle(extensionStatusStyle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(extensionStatusTitle)

            Button(
                "Open Safari Settings",
                systemImage: "safari",
                action: openSafariSettings
            )
        } header: {
            Text("Safari Extension")
        } footer: {
            Text("Enable the extension, then allow website access for all websites to send supported downloads to SDM.")
        }

        Section("About") {
            if let selectedDescriptor {
                NavigationLink {
                    DownloadEngineInformationView(
                        descriptor: selectedDescriptor,
                        databaseURL: databaseURL
                    )
                } label: {
                    Label("Engine Information", systemImage: "info.circle")
                }
            }

            NavigationLink {
                LegalNoticesView()
            } label: {
                Label("Third-Party Licenses", systemImage: "doc.text")
            }
        }
    }

    private var extensionStatusTitle: String {
        switch safariExtensionIsEnabled {
        case true: "Enabled"
        case false: "Disabled"
        case nil: "Manage in Settings"
        }
    }

    private var extensionStatusStyle: Color {
        safariExtensionIsEnabled == true ? .green : .secondary
    }

    private var currentFolderName: String {
        if defaultDownloadLocation == .appSandbox {
            DefaultDownloadLocation.appSandbox.title
        } else {
            defaultDestinationDirectory.lastPathComponent
        }
    }
}
#endif
