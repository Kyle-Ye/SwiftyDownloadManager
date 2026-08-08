#if os(macOS)
import SDMCore
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    let service: DownloadService
    @AppStorage(AppStorageKey.defaultConnectionCount) private var defaultConnectionCount = 8
    @State private var selection: DownloadFilter? = .all
    @State private var selectedDownloadIDs: Set<DownloadID> = []
    @State private var downloadsPendingRemoval: Set<DownloadID> = []
    @State private var confirmsBatchRemoval = false
    @State private var showsNewDownload = false
    @State private var presentedError: PresentedDownloadError?

    private var selectedFilter: DownloadFilter {
        selection ?? .all
    }

    private var visibleSnapshots: [DownloadSnapshot] {
        service.snapshots
            .filter { selectedFilter.includes($0.state) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedSnapshot: DownloadSnapshot? {
        guard selectedDownloadIDs.count == 1, let selectedID = selectedDownloadIDs.first else {
            return nil
        }
        return service.snapshots.first { $0.id == selectedID }
    }

    private var selectedCommands: [DownloadCommand] {
        service.snapshots.commonCommands(for: selectedDownloadIDs)
    }

    private var selectedDownloadsAreBusy: Bool {
        !service.commandInFlightIDs.isDisjoint(with: selectedDownloadIDs)
    }

    private var availableNewURLAction: (() -> Void)? {
        if service.initializationError == nil {
            presentNewDownload
        } else {
            nil
        }
    }

    var body: some View {
        NavigationSplitView {
            DownloadSidebar(snapshots: service.snapshots, selection: $selection)
        } detail: {
            detail
                .navigationTitle(selectedFilter.rawValue)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showsNewDownload) {
            NewDownloadView(
                defaultConnectionCount: defaultConnectionCount,
                destinationDirectory: service.defaultDestinationDirectory,
                engine: selectedEngineDescriptor
            ) { url, destinationDirectory, connectionCount in
                _ = try await service.enqueue(
                    url: url,
                    destinationDirectory: destinationDirectory,
                    connectionCount: connectionCount
                )
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
            selectedDownloadIDs.removeAll()
        }
        .onChange(of: Set(service.snapshots.map(\.id))) { _, availableIDs in
            selectedDownloadIDs.formIntersection(availableIDs)
        }
        .onOpenURL(perform: handleExternalURL)
        .onReceive(
            NotificationCenter.default.publisher(for: .browserDownloadCallback)
        ) { notification in
            guard let callbackURL = notification.object as? URL else { return }
            handleExternalURL(callbackURL)
        }
        .focusedSceneValue(\.newURLAction, availableNewURLAction)
    }

    @ViewBuilder
    private var detail: some View {
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
                .keyboardShortcut("n", modifiers: .command)
            }
        } else {
            Table(visibleSnapshots, selection: $selectedDownloadIDs) {
                TableColumn("Name") { snapshot in
                    DownloadNameCell(snapshot: snapshot)
                }
                .width(min: 180, ideal: 260)

                TableColumn("Size") { snapshot in
                    Text(DownloadFormatting.bytes(snapshot.contentLength))
                        .monospacedDigit()
                }
                .width(min: 72, ideal: 90)

                TableColumn("Progress") { snapshot in
                    DownloadProgressCell(snapshot: snapshot)
                }
                .width(min: 140, ideal: 190)

                TableColumn("Status") { snapshot in
                    Label(snapshot.state.title, systemImage: snapshot.state.systemImage)
                        .foregroundStyle(snapshot.state.tint)
                }
                .width(min: 110, ideal: 130)

                TableColumn("Speed") { snapshot in
                    Text(DownloadFormatting.speed(snapshot.bytesPerSecond))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)

                TableColumn("Remaining") { snapshot in
                    Text(DownloadFormatting.duration(snapshot.estimatedTimeRemaining))
                        .monospacedDigit()
                }
                .width(min: 72, ideal: 90)

                TableColumn("Updated") { snapshot in
                    Text(
                        snapshot.updatedAt,
                        format: .dateTime.month().day().hour().minute()
                    )
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120)

                TableColumn("") { snapshot in
                    DownloadActionsMenu(
                        snapshot: snapshot,
                        isBusy: service.commandInFlightIDs.contains(snapshot.id),
                        showInfo: { openInfo(snapshot.id) },
                        deleteFile: { deleteFileAndHistory(snapshot) }
                    ) { command in
                        perform(command, on: snapshot.id)
                    }
                }
                .width(34)
            }
            .background(MutedTableSelection(selectedIDs: selectedDownloadIDs))
            .contextMenu(forSelectionType: DownloadID.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Show Info", systemImage: "info.circle") {
                        openInfo(id)
                    }
                }

                ForEach(service.snapshots.commonCommands(for: ids)) { command in
                    Button(role: command.role) {
                        performSelectedCommand(command, on: ids)
                    } label: {
                        Label(
                            command.title(forSelectionCount: ids.count),
                            systemImage: command.systemImage
                        )
                    }
                    .disabled(!service.commandInFlightIDs.isDisjoint(with: ids))
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first {
                    openInfo(id)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if let selectedSnapshot {
                Button("Info", systemImage: "info.circle") {
                    openInfo(selectedSnapshot.id)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            ForEach(selectedCommands) { command in
                Button(role: command.role) {
                    performSelectedCommand(command, on: selectedDownloadIDs)
                } label: {
                    Label(
                        command.title(forSelectionCount: selectedDownloadIDs.count),
                        systemImage: command.systemImage
                    )
                }
                .disabled(selectedDownloadsAreBusy)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button("New Download", systemImage: "plus", action: presentNewDownload)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(service.initializationError != nil)
        }
    }

    private var emptyTitle: String {
        selectedFilter == .all ? "No Downloads" : "No \(selectedFilter.rawValue)"
    }

    private var selectedEngineDescriptor: DownloadEngineDescriptor {
        service.selectedEngineDescriptor
    }

    private var emptyDescription: String {
        if selectedFilter == .all {
            return "Add a direct HTTP or HTTPS URL to start a download."
        }
        return "Downloads matching this filter will appear here."
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

    private func deleteFileAndHistory(_ snapshot: DownloadSnapshot) {
        Task { @MainActor in
            do {
                try await service.deleteDownloadedFileAndHistory(for: snapshot.id)
                selectedDownloadIDs.remove(snapshot.id)
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not Delete Downloaded File",
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
            confirmRemoval(of: ids)
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

    private func confirmRemoval(of ids: Set<DownloadID>) {
        downloadsPendingRemoval = ids
        confirmsBatchRemoval = true
    }

    private func removePendingDownloads() {
        let ids = downloadsPendingRemoval
        Task { @MainActor in
            do {
                let removedIDs = try await service.perform(.remove, on: ids)
                selectedDownloadIDs.subtract(removedIDs)
                downloadsPendingRemoval.removeAll()
            } catch {
                presentedError = PresentedDownloadError(
                    title: "Could Not Remove Downloads",
                    error: error
                )
            }
        }
    }

    private func openInfo(_ id: DownloadID) {
        openWindow(value: id)
    }

    private func presentNewDownload() {
        showsNewDownload = true
    }

    private func handleExternalURL(_ callbackURL: URL) {
        guard let request = BrowserDownloadRequest(callbackURL: callbackURL) else { return }

        Task { @MainActor in
            do {
                _ = try await service.enqueue(
                    url: request.url,
                    suggestedFilename: request.suggestedFilename,
                    connectionCount: selectedEngineDescriptor.supports(
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

private struct DownloadNameCell: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.displayFilename)
                .lineLimit(1)
            Text(snapshot.sourceURL.host() ?? snapshot.sourceURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(snapshot.sourceURL.absoluteString)
    }
}

private struct DownloadProgressCell: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let progress = snapshot.progressFraction {
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text(DownloadFormatting.bytes(snapshot.downloadedBytes))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DownloadActionsMenu: View {
    let snapshot: DownloadSnapshot
    let isBusy: Bool
    let showInfo: () -> Void
    let deleteFile: () -> Void
    let perform: (DownloadCommand) -> Void
    @State private var confirmsFileDeletion = false

    var body: some View {
        Menu("Download Actions", systemImage: isBusy ? "ellipsis.circle.fill" : "ellipsis.circle") {
            Button("Show Info", systemImage: "info.circle", action: showInfo)

            if !snapshot.availableCommands.isEmpty {
                Divider()
            }

            ForEach(snapshot.availableCommands) { command in
                Button(role: command.role) {
                    perform(command)
                } label: {
                    Label(command.title, systemImage: command.systemImage)
                }
                .disabled(isBusy)
            }

            if snapshot.state == .completed, snapshot.destinationURL != nil {
                Divider()
                Button(
                    "Delete Downloaded File…",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    confirmsFileDeletion = true
                }
                .disabled(isBusy)
            }
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.iconOnly)
        .help("Download Actions")
        .confirmationDialog(
            "Delete Downloaded File?",
            isPresented: $confirmsFileDeletion
        ) {
            Button("Delete File and Remove History", role: .destructive, action: deleteFile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(snapshot.displayFilename) will be permanently deleted from disk.")
        }
    }
}

#Preview {
    ContentView(service: .preview())
}
#endif
