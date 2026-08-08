import SDMCore
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @AppStorage(AppStorageKey.downloadEngine) private var selectedEngine = DownloadEngineKind.libcurl.rawValue
    #if os(macOS)
    @AppStorage(AppStorageKey.showsMenuBarIcon) private var showsMenuBarIcon = true
    #endif
    @State private var safariExtensionIsEnabled: Bool?
    @State private var presentedError: PresentedDownloadError?
    #if os(macOS)
    @State private var showsLegalNotices = false
    #endif
    @Bindable var service: DownloadService

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
                showsMenuBarIcon: $showsMenuBarIcon,
                selectedEngine: $selectedEngine,
                engineDescriptors: service.engineDescriptors,
                selectedDescriptor: selectedDescriptor,
                safariExtensionIsEnabled: safariExtensionIsEnabled,
                databaseURL: service.databaseURL,
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
    #endif
}

#Preview {
    NavigationStack {
        SettingsView(service: .preview())
            .navigationTitle("Settings")
    }
}
