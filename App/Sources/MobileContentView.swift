#if os(iOS)
import SDMCore
import SwiftUI

struct MobileContentView: View {
    @Bindable var service: DownloadService
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @State private var selectedFilter = DownloadFilter.all
    @State private var showsNewDownload = false
    @State private var showsSettings = false
    @State private var presentedError: PresentedDownloadError?

    private var visibleSnapshots: [DownloadSnapshot] {
        service.snapshots
            .filter { selectedFilter.includes($0.state) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let initializationError = service.initializationError {
                    ContentUnavailableView {
                        Label("Download Engine Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(initializationError)
                            .textSelection(.enabled)
                    }
                } else if service.isLoadingHistory {
                    ProgressView("Loading Download History…")
                        .controlSize(.large)
                } else if visibleSnapshots.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: selectedFilter.systemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button("New Download", action: presentNewDownload)
                    }
                } else {
                    List(visibleSnapshots) { snapshot in
                        NavigationLink(value: snapshot.id) {
                            MobileDownloadRow(snapshot: snapshot)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            ForEach(snapshot.availableCommands) { command in
                                Button(command.title, systemImage: command.systemImage) {
                                    perform(command, on: snapshot.id)
                                }
                                .tint(command == .remove || command == .cancel ? .red : .accentColor)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(selectedFilter.rawValue)
            .navigationDestination(for: DownloadID.self) { id in
                DownloadInfoView(service: service, downloadID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Filter", systemImage: selectedFilter.systemImage) {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(DownloadFilter.allCases) { filter in
                                Label(filter.rawValue, systemImage: filter.systemImage)
                                    .tag(filter)
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showsSettings = true
                    }
                    Button("New Download", systemImage: "plus", action: presentNewDownload)
                        .disabled(service.initializationError != nil)
                }
            }
        }
        .sheet(isPresented: $showsNewDownload) {
            NewDownloadView(
                defaultConnectionCount: defaultConnectionCount,
                destinationDirectory: service.defaultDestinationDirectory,
                engine: service.selectedEngineDescriptor
            ) { url, destinationDirectory, connectionCount in
                _ = try await service.enqueue(
                    url: url,
                    destinationDirectory: destinationDirectory,
                    connectionCount: connectionCount
                )
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView(service: service)
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showsSettings = false
                            }
                        }
                    }
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onOpenURL(perform: handleExternalURL)
    }

    private var emptyTitle: String {
        selectedFilter == .all ? "No Downloads" : "No \(selectedFilter.rawValue)"
    }

    private var emptyDescription: String {
        selectedFilter == .all
            ? "Add a direct HTTP or HTTPS URL to start a download."
            : "Downloads matching this filter will appear here."
    }

    private func presentNewDownload() {
        showsNewDownload = true
    }

    private func perform(_ command: DownloadCommand, on id: DownloadID) {
        Task { @MainActor in
            do {
                try await service.perform(command, on: id)
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not \(command.title)",
                    error: error
                )
            }
        }
    }

    private func handleExternalURL(_ callbackURL: URL) {
        guard let request = BrowserDownloadRequest(callbackURL: callbackURL) else { return }
        Task { @MainActor in
            do {
                _ = try await service.enqueue(
                    url: request.url,
                    suggestedFilename: request.suggestedFilename,
                    connectionCount: service.selectedEngineDescriptor.supports(
                        .multiConnectionTransfers
                    ) ? defaultConnectionCount : 1
                )
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not Add Browser Download",
                    error: error
                )
            }
        }
    }
}
#endif
