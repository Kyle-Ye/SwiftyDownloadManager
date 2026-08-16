#if os(iOS)
import SDMCore
import SwiftUI

struct MobileContentView: View {
    @Environment(\.editMode) private var editMode
    @Bindable var service: DownloadService
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @State private var selection: DownloadFilter? = .all
    @State private var selectedDownloadIDs: Set<DownloadID> = []
    @State private var downloadsPendingRemoval: Set<DownloadID> = []
    @State private var confirmsBatchRemoval = false
    @State private var showsNewDownload = false
    @State private var showsSettings = false
    @State private var presentedError: PresentedDownloadError?
    @State private var didPresentDestinationRecovery = false

    private var selectedFilter: DownloadFilter {
        selection ?? .all
    }

    private var visibleSnapshots: [DownloadSnapshot] {
        service.snapshots
            .filter { selectedFilter.includes($0.state) }
            .sortedForDownloadList()
    }

    private var selectedCommands: [DownloadCommand] {
        service.snapshots.commonCommands(for: selectedDownloadIDs)
    }

    private var selectedDownloadsAreBusy: Bool {
        !service.commandInFlightIDs.isDisjoint(with: selectedDownloadIDs)
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        NavigationSplitView {
            DownloadSidebar(snapshots: service.snapshots, selection: $selection)
        } detail: {
            NavigationStack {
                Group {
                    if let initializationError = service.initializationError {
                        ContentUnavailableView {
                            Label(
                                "Download Engine Unavailable",
                                systemImage: "exclamationmark.triangle"
                            )
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
                        List(visibleSnapshots, selection: $selectedDownloadIDs) { snapshot in
                            NavigationLink(value: snapshot.id) {
                                MobileDownloadRow(snapshot: snapshot)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                ForEach(snapshot.availableCommands) { command in
                                    Button(command.title, systemImage: command.systemImage) {
                                        perform(command, on: snapshot.id)
                                    }
                                    .tint(
                                        command == .remove || command == .cancel
                                            ? .red
                                            : .accentColor
                                    )
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
                        EditButton()
                            .disabled(visibleSnapshots.isEmpty)
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") {
                            showsSettings = true
                        }
                        Button("New Download", systemImage: "plus", action: presentNewDownload)
                            .disabled(service.initializationError != nil)
                    }

                    if isEditing {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            ForEach(selectedCommands) { command in
                                Button(role: command.role) {
                                    performSelectedCommand(
                                        command,
                                        on: selectedDownloadIDs
                                    )
                                } label: {
                                    Label(
                                        command.title(
                                            forSelectionCount: selectedDownloadIDs.count
                                        ),
                                        systemImage: command.systemImage
                                    )
                                }
                                .disabled(selectedDownloadsAreBusy)
                            }
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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
        .confirmationDialog(
            removalConfirmationTitle,
            isPresented: $confirmsBatchRemoval
        ) {
            Button("Remove from History", role: .destructive, action: removePendingDownloads)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Partial data and diagnostics for the selected downloads will be deleted. "
                    + "Downloaded files will be kept."
            )
        }
        .onChange(of: selection) { _, _ in
            finishEditing()
        }
        .onChange(of: Set(service.snapshots.map(\.id))) { _, availableIDs in
            selectedDownloadIDs.formIntersection(availableIDs)
        }
        .onOpenURL(perform: handleExternalURL)
        .task {
            presentDestinationRecoveryIfNeeded()
        }
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

    private func presentDestinationRecoveryIfNeeded() {
        guard !didPresentDestinationRecovery,
              let message = service.defaultDestinationRecoveryMessage else { return }
        didPresentDestinationRecovery = true
        presentedError = PresentedDownloadError(
            title: "External Folder Unavailable",
            message: message
        )
    }

    private func perform(_ command: DownloadCommand, on id: DownloadID) {
        Task { @MainActor in
            do {
                let didPerform = try await service.perform(command, on: id)
                if didPerform, command == .remove {
                    selectedDownloadIDs.remove(id)
                }
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not \(command.title)",
                    error: error
                )
            }
        }
    }

    private var removalConfirmationTitle: String {
        if downloadsPendingRemoval.count == 1 {
            "Remove Download from History?"
        } else {
            "Remove \(downloadsPendingRemoval.count) Downloads from History?"
        }
    }

    private func performSelectedCommand(
        _ command: DownloadCommand,
        on ids: Set<DownloadID>
    ) {
        guard !ids.isEmpty else { return }
        if command == .remove {
            downloadsPendingRemoval = ids
            confirmsBatchRemoval = true
        } else {
            perform(command, on: ids)
        }
    }

    private func perform(_ command: DownloadCommand, on ids: Set<DownloadID>) {
        Task { @MainActor in
            do {
                _ = try await service.perform(command, on: ids)
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not \(command.title) Downloads",
                    error: error
                )
            }
        }
    }

    private func removePendingDownloads() {
        let ids = downloadsPendingRemoval
        Task { @MainActor in
            do {
                let removedIDs = try await service.perform(.remove, on: ids)
                selectedDownloadIDs.subtract(removedIDs)
                downloadsPendingRemoval.removeAll()
                if selectedDownloadIDs.isEmpty {
                    editMode?.wrappedValue = .inactive
                }
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not Remove Downloads",
                    error: error
                )
            }
        }
    }

    private func finishEditing() {
        selectedDownloadIDs.removeAll()
        editMode?.wrappedValue = .inactive
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
