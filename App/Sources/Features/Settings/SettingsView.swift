import SDMCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @AppStorage(AppStorageKey.downloadEngine) private var selectedEngine = DownloadEngineKind.libcurl.rawValue
    #if os(macOS)
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    @State private var defaultDownloadLocation: DefaultDownloadLocation
    @State private var locationBeforeCustomPicker: DefaultDownloadLocation?
    @State private var showsCustomDestinationPicker = false
    #endif
    @State private var safariExtensionIsEnabled: Bool?
    @State private var presentedError: PresentedDownloadError?
    #if os(macOS)
    @State private var showsLegalNotices = false
    #endif
    @Bindable var service: DownloadService

    init(service: DownloadService) {
        self.service = service
        #if os(macOS)
        _defaultDownloadLocation = State(initialValue: service.defaultDownloadLocation)
        #endif
    }

    var body: some View {
        Form {
            #if os(iOS)
            MobileSettingsFormContent(
                defaultConnectionCount: $defaultConnectionCount,
                selectedEngine: $selectedEngine,
                engineDescriptors: service.engineDescriptors,
                selectedDescriptor: selectedDescriptor,
                safariExtensionIsEnabled: safariExtensionIsEnabled,
                databaseURL: service.databaseURL,
                openSafariSettings: SafariExtensionSupport.showPreferences
            )
            #else
            MacSettingsFormContent(
                defaultConnectionCount: $defaultConnectionCount,
                defaultDownloadLocation: $defaultDownloadLocation,
                showsMenuBarIcon: $showsMenuBarIcon,
                selectedEngine: $selectedEngine,
                engineDescriptors: service.engineDescriptors,
                selectedDescriptor: selectedDescriptor,
                safariExtensionIsEnabled: safariExtensionIsEnabled,
                databaseURL: service.databaseURL,
                defaultDestinationDirectory: service.defaultDestinationDirectory,
                chooseCustomDefaultDestination: presentCustomDestinationPicker,
                openSafariSettings: SafariExtensionSupport.showPreferences,
                showBrowserExtensions: showBrowserExtensions,
                showLegalNotices: { showsLegalNotices = true }
            )
            #endif
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollContentBackground(.visible)
        #else
        .padding()
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
        #if os(macOS)
        .onChange(of: defaultDownloadLocation) { oldLocation, newLocation in
            applyDefaultDownloadLocation(
                from: oldLocation,
                to: newLocation
            )
        }
        .fileImporter(
            isPresented: $showsCustomDestinationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: applyCustomDestination,
            onCancellation: cancelCustomDestinationPicker
        )
        #endif
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        #if os(macOS)
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
        #endif
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

    #if os(macOS)
    private func showBrowserExtensions() {
        openWindow(id: AppWindowID.browsers)
    }

    private func applyDefaultDownloadLocation(
        from oldLocation: DefaultDownloadLocation,
        to newLocation: DefaultDownloadLocation
    ) {
        guard newLocation != service.defaultDownloadLocation else { return }
        if newLocation == .custom, !service.hasStoredCustomDefaultDestination {
            locationBeforeCustomPicker = oldLocation
            showsCustomDestinationPicker = true
            return
        }

        do {
            try service.selectDefaultDestination(newLocation)
        } catch {
            defaultDownloadLocation = service.defaultDownloadLocation
            presentedError = PresentedDownloadError(
                title: "Could Not Change Default Save Location",
                error: error
            )
        }
    }

    private func presentCustomDestinationPicker() {
        locationBeforeCustomPicker = service.defaultDownloadLocation
        showsCustomDestinationPicker = true
    }

    private func applyCustomDestination(_ result: Result<[URL], Error>) {
        do {
            guard let directory = try result.get().first else {
                cancelCustomDestinationPicker()
                return
            }
            try service.selectDefaultDestination(
                .custom,
                customDirectory: directory
            )
            defaultDownloadLocation = .custom
            locationBeforeCustomPicker = nil
        } catch {
            defaultDownloadLocation = locationBeforeCustomPicker
                ?? service.defaultDownloadLocation
            locationBeforeCustomPicker = nil
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            presentedError = PresentedDownloadError(
                title: "Could Not Choose Default Save Location",
                error: error
            )
        }
    }

    private func cancelCustomDestinationPicker() {
        defaultDownloadLocation = locationBeforeCustomPicker
            ?? service.defaultDownloadLocation
        locationBeforeCustomPicker = nil
    }
    #endif
}

#Preview {
    NavigationStack {
        SettingsView(service: .preview())
            .navigationTitle("Settings")
    }
}
