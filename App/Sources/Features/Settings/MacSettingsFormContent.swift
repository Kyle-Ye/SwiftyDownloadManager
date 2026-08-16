#if os(macOS)
import SDMCore
import SwiftUI

struct MacSettingsFormContent: View {
    @Binding var defaultConnectionCount: Int
    @Binding var defaultDownloadLocation: DefaultDownloadLocation
    @Binding var showsMenuBarIcon: Bool
    @Binding var menuBarRecentDownloadLimit: Int
    @Binding var showsLockScreenDownloadStatus: Bool
    @Binding var lockScreenRecentDownloadLimit: Int
    @Binding var selectedEngine: String
    let engineDescriptors: [DownloadEngineDescriptor]
    let selectedDescriptor: DownloadEngineDescriptor?
    let safariExtensionIsEnabled: Bool?
    let databaseURL: URL?
    let defaultDestinationDirectory: URL
    let chooseCustomDefaultDestination: () -> Void
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

            Stepper(
                "Menu Bar recent downloads: \(menuBarRecentDownloadLimit)",
                value: $menuBarRecentDownloadLimit,
                in: RecentDownloads.allowedMaximumCountRange
            )
            .disabled(!showsMenuBarIcon)

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
            Picker("Default save location", selection: $defaultDownloadLocation) {
                ForEach(DefaultDownloadLocation.availableLocations) { location in
                    Text(location.title)
                        .tag(location)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Current folder") {
                Text(defaultDestinationPath)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if defaultDownloadLocation == .custom {
                Button("Choose Custom Folder…", action: chooseCustomDefaultDestination)
            }

            Stepper(
                "Default connections: \(defaultConnectionCount)",
                value: $defaultConnectionCount,
                in: 1 ... 16
            )
            .disabled(selectedDescriptor?.supports(.multiConnectionTransfers) == false)
        } header: {
            Text("Downloads")
        } footer: {
            VStack(alignment: .leading) {
                Text("New downloads use this folder by default. You can still choose a different folder for an individual download.")
                if selectedDescriptor?.supports(.multiConnectionTransfers) == false {
                    Text("URLSession manages connections internally and uses one connection per download.")
                }
            }
        }

        Section {
            Toggle(
                "Show download status on the Lock Screen",
                isOn: $showsLockScreenDownloadStatus
            )

            Stepper(
                "Lock Screen recent downloads: \(lockScreenRecentDownloadLimit)",
                value: $lockScreenRecentDownloadLimit,
                in: RecentDownloads.allowedMaximumCountRange
            )
            .disabled(!showsLockScreenDownloadStatus)
        } header: {
            Text("Lock Screen")
        } footer: {
            Text(
                "Shows recent download progress while this Mac is locked. "
                    + "When no downloads are available, SDM shows an empty state."
            )
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

    private var defaultDestinationPath: String {
        defaultDestinationDirectory.path(percentEncoded: false)
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
