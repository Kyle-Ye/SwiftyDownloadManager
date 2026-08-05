import SDMCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @AppStorage(AppStorageKey.downloadEngine) private var selectedEngine = DownloadEngineKind.libcurl.rawValue
    @State private var safariExtensionIsEnabled: Bool?
    @State private var presentedError: PresentedDownloadError?
    @State private var showsLegalNotices = false
    @Bindable var service: DownloadService

    var body: some View {
        Form {
            Section("General") {
                #if os(macOS)
                Picker("Application icon location", selection: $showsMenuBarIcon) {
                    Text("In Dock and Menu Bar")
                        .tag(true)
                    Text("In Dock only")
                        .tag(false)
                }
                .pickerStyle(.menu)
                #endif

                Picker("Download engine", selection: $selectedEngine) {
                    ForEach(service.engineDescriptors) { descriptor in
                        Text(descriptor.kind.title)
                            .tag(descriptor.kind.rawValue)
                    }
                }
                .pickerStyle(.menu)

                if let descriptor = selectedDescriptor {
                    ForEach(DownloadFeature.allCases) { feature in
                        Label(
                            feature.title,
                            systemImage: descriptor.supports(feature)
                                ? "checkmark.circle.fill"
                                : "xmark.circle"
                        )
                        .foregroundStyle(
                            descriptor.supports(feature) ? .primary : .secondary
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

            Section("Safari Extension") {
                LabeledContent("Status") {
                    Text(extensionStatusTitle)
                        .foregroundStyle(extensionStatusColor)
                }

                #if os(macOS)
                Text("Enable the extension in Safari, then allow website access. Download links and the Download with SDM context menu will send supported HTTP and HTTPS files to SDM.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #else
                Text("Enable the extension in Safari, then set Website Access to Allow on All Websites. Supported HTTP and HTTPS download links will open in SDM.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #endif

                Button("Open Safari Extension Settings") {
                    SafariExtensionSupport.showPreferences()
                }
            }

            Section("Engine") {
                LabeledContent("Version", value: SDMCoreInfo.engineVersion)
                LabeledContent("libcurl", value: SDMCoreInfo.libcurlVersion)
                LabeledContent("ABI", value: String(SDMCoreInfo.engineABIVersion))
                if let databaseURL = service.databaseURL {
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

                Button("View Third-Party Licenses") {
                    showsLegalNotices = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .task {
            await refreshSafariExtensionState()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshSafariExtensionState()
            }
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshSafariExtensionState()
            }
        }
        #endif
        .onChange(of: selectedEngine) { _, _ in
            applyEngineSelection()
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showsLegalNotices) {
            NavigationStack {
                LegalNoticesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showsLegalNotices = false
                            }
                        }
                    }
            }
        }
    }

    private var extensionStatusTitle: String {
        switch safariExtensionIsEnabled {
        case true: "Enabled"
        case false: "Disabled"
        #if os(macOS)
        case nil: "Checking…"
        #else
        case nil: "Manage in Settings"
        #endif
        }
    }

    private var extensionStatusColor: Color {
        switch safariExtensionIsEnabled {
        case true: .green
        case false: .secondary
        case nil: .secondary
        }
    }

    private var selectedDescriptor: DownloadEngineDescriptor? {
        guard let kind = DownloadEngineKind(rawValue: selectedEngine) else { return nil }
        return service.engineDescriptors.first { $0.kind == kind }
    }

    private func refreshSafariExtensionState() async {
        safariExtensionIsEnabled = await SafariExtensionSupport.isEnabled()
    }

    private func applyEngineSelection() {
        guard let engine = DownloadEngineKind(rawValue: selectedEngine),
              engine != service.selectedEngine else { return }
        Task { @MainActor in
            do {
                try await service.selectEngine(engine)
            } catch {
                selectedEngine = service.selectedEngine.rawValue
                presentedError = PresentedDownloadError(
                    title: "Could Not Change Download Engine",
                    error: error
                )
            }
        }
    }
}

#Preview {
    SettingsView(service: .preview())
}
