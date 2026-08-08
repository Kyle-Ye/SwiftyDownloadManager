import Foundation
import Observation
import SDMCore

/// App-layer adapter that owns the engine lifecycle and publishes immutable
/// snapshots from both download backends for SwiftUI.
@Observable
@MainActor
final class DownloadService {
    private(set) var snapshots: [DownloadSnapshot]
    private(set) var isLoadingHistory: Bool
    private(set) var commandInFlightIDs: Set<DownloadID> = []
    private(set) var logsByDownloadID: [DownloadID: [DownloadDiagnosticEvent]] = [:]
    private(set) var engineDescriptors: [DownloadEngineDescriptor] = []
    private(set) var selectedEngine: DownloadEngineKind

    let defaultDestinationDirectory: URL
    let databaseURL: URL?
    let initializationError: String?

    private let manager: DownloadManager?
    private let destinationBookmarks: DestinationBookmarkStore?
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var previousSnapshots: [DownloadID: DownloadSnapshot] = [:]

    init(
        configuration: DownloadManagerConfiguration,
        destinationDirectory: URL = FileManager.default.temporaryDirectory,
        destinationBookmarks: DestinationBookmarkStore? = nil
    ) throws {
        manager = try DownloadManager(configuration: configuration)
        selectedEngine = configuration.defaultEngine
        self.destinationBookmarks = destinationBookmarks
        defaultDestinationDirectory = destinationDirectory
        databaseURL = configuration.databaseURL
        initializationError = nil
        snapshots = []
        isLoadingHistory = true
        startObserving()
        loadEngineDescriptors()
    }

    private init(
        manager: DownloadManager?,
        destinationDirectory: URL,
        databaseURL: URL?,
        destinationBookmarks: DestinationBookmarkStore?,
        initializationError: String?,
        snapshots: [DownloadSnapshot]
    ) {
        self.manager = manager
        self.destinationBookmarks = destinationBookmarks
        defaultDestinationDirectory = destinationDirectory
        self.databaseURL = databaseURL
        self.initializationError = initializationError
        selectedEngine = .libcurl
        self.snapshots = []
        isLoadingHistory = false
        startObserving()
        ingest(snapshots)
    }

    static func live(fileManager: FileManager = .default) -> DownloadService {
        do {
            let storagePaths = try AppStoragePaths.live(fileManager: fileManager)
            let destinationBookmarks = try? DestinationBookmarkStore(
                storeURL: storagePaths.destinationBookmarksURL
            )
            #if os(macOS)
            let destinationSearchPath: FileManager.SearchPathDirectory = .downloadsDirectory
            #else
            let destinationSearchPath: FileManager.SearchPathDirectory = .documentDirectory
            #endif
            guard let destinationDirectory = fileManager.urls(
                for: destinationSearchPath,
                in: .userDomainMask
            ).first else {
                throw ServiceError.unavailable(
                    "The Downloads directory could not be located."
                )
            }

            return try DownloadService(
                configuration: storagePaths.managerConfiguration(
                    defaultEngine: storedEngine,
                    urlSessionIdentifier: Bundle.main.bundleIdentifier.map {
                        "\($0).urlsession-downloads"
                    }
                ),
                destinationDirectory: destinationDirectory,
                destinationBookmarks: destinationBookmarks
            )
        } catch {
            return DownloadService(
                manager: nil,
                destinationDirectory: fileManager.temporaryDirectory,
                databaseURL: nil,
                destinationBookmarks: nil,
                initializationError: Self.message(for: error),
                snapshots: []
            )
        }
    }

    static func preview(snapshots: [DownloadSnapshot] = []) -> DownloadService {
        DownloadService(
            manager: nil,
            destinationDirectory: FileManager.default.temporaryDirectory,
            databaseURL: nil,
            destinationBookmarks: nil,
            initializationError: nil,
            snapshots: snapshots
        )
    }

    func enqueue(
        url: URL,
        destinationDirectory: URL? = nil,
        suggestedFilename: String? = nil,
        connectionCount: Int
    ) async throws -> DownloadID {
        let manager = try requiredManager()
        let requestedDestination = destinationDirectory ?? defaultDestinationDirectory
        let authorizedDestination: URL
        if requestedDestination.standardizedFileURL !=
            defaultDestinationDirectory.standardizedFileURL {
            guard let destinationBookmarks else {
                throw ServiceError.unavailable(
                    "Persistent access to custom download folders is unavailable."
                )
            }
            authorizedDestination = try destinationBookmarks.authorize(
                requestedDestination
            )
        } else {
            authorizedDestination = requestedDestination
        }
        let request = DownloadRequest(
            url: url,
            destinationDirectory: authorizedDestination,
            filename: suggestedFilename,
            connectionLimit: connectionCount
        )
        return try await manager.enqueue(request)
    }

    var selectedEngineDescriptor: DownloadEngineDescriptor {
        engineDescriptors.first { $0.kind == selectedEngine }
            ?? DownloadEngineDescriptor(
                kind: selectedEngine,
                version: "",
                features: selectedEngine == .libcurl
                    ? [.multiConnectionTransfers, .bandwidthLimiting]
                    : [.backgroundTransfers],
                maximumConnectionsPerDownload: selectedEngine == .libcurl ? 16 : 1
            )
    }

    func selectEngine(_ engine: DownloadEngineKind) async throws {
        let manager = try requiredManager()
        try await manager.setDefaultEngine(engine)
        selectedEngine = engine
    }

    @discardableResult
    func perform(_ command: DownloadCommand, on id: DownloadID) async throws -> Bool {
        guard let snapshot = snapshots.first(where: { $0.id == id }),
              snapshot.state.allows(command) else {
            return false
        }
        let manager = try requiredManager()
        guard commandInFlightIDs.insert(id).inserted else { return false }
        defer { commandInFlightIDs.remove(id) }

        switch command {
        case .pause:
            try await manager.pause(id)
        case .resume:
            try await manager.resume(id)
        case .cancel:
            try await manager.cancel(id)
        case .retry:
            try await manager.retry(id)
        case .remove:
            try await manager.remove(id)
        }
        return true
    }

    @discardableResult
    func perform(
        _ command: DownloadCommand,
        on ids: Set<DownloadID>
    ) async throws -> Set<DownloadID> {
        guard commandInFlightIDs.isDisjoint(with: ids) else {
            throw ServiceError.unavailable(
                "Another operation is already in progress for one of the selected downloads."
            )
        }
        var performedIDs: Set<DownloadID> = []
        for id in ids {
            if try await perform(command, on: id) {
                performedIDs.insert(id)
            }
        }
        return performedIDs
    }

    func logs(for id: DownloadID) -> [DownloadDiagnosticEvent] {
        logsByDownloadID[id] ?? []
    }

    func refreshLogs(for id: DownloadID) async {
        guard let manager else { return }
        do {
            logsByDownloadID[id] = try await manager.diagnosticEvents(for: id)
        } catch let error as DownloadError where error.code == .notFound {
            logsByDownloadID[id] = nil
        } catch {
            // Snapshot observation remains usable when diagnostics cannot load.
        }
    }

    func deleteDownloadedFileAndHistory(for id: DownloadID) async throws {
        let manager = try requiredManager()
        guard let snapshot = snapshots.first(where: { $0.id == id }),
              snapshot.state == .completed,
              let destinationURL = snapshot.destinationURL else {
            throw ServiceError.unavailable("The completed download file is unavailable.")
        }
        try FileManager.default.removeItem(at: destinationURL)
        try await manager.remove(id)
    }

    func shutdown() async {
        observationTask?.cancel()
        observationTask = nil
        if let manager {
            await manager.shutdown()
        }
        destinationBookmarks?.stopAllAccess()
    }

    deinit {
        observationTask?.cancel()
    }

    private func startObserving() {
        guard let manager else { return }
        observationTask = Task { [weak self, manager] in
            for await update in await manager.updates() {
                guard !Task.isCancelled else { return }
                self?.ingest(update.snapshots)
            }
        }
    }

    private func loadEngineDescriptors() {
        guard let manager else { return }
        Task { [weak self, manager] in
            self?.engineDescriptors = await manager.engineDescriptors()
        }
    }

    private func ingest(_ nextSnapshots: [DownloadSnapshot]) {
        let nextByID = Dictionary(uniqueKeysWithValues: nextSnapshots.map { ($0.id, $0) })
        for snapshot in nextSnapshots {
            let previous = previousSnapshots[snapshot.id]
            if previous == nil || previous?.state != snapshot.state ||
                previous?.error != snapshot.error {
                Task { [weak self] in
                    await self?.refreshLogs(for: snapshot.id)
                }
            }
        }
        for removedID in previousSnapshots.keys where nextByID[removedID] == nil {
            logsByDownloadID[removedID] = nil
        }
        previousSnapshots = nextByID
        snapshots = nextSnapshots
        isLoadingHistory = false
    }

    private func requiredManager() throws -> DownloadManager {
        guard let manager else {
            throw ServiceError.unavailable(
                initializationError ?? "The download engine is unavailable."
            )
        }
        return manager
    }

    nonisolated static func message(for error: Error) -> String {
        if let downloadError = error as? DownloadError {
            return downloadError.message
        }
        return error.localizedDescription
    }

    private enum ServiceError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case let .unavailable(message):
                message
            }
        }
    }


    private static var storedEngine: DownloadEngineKind {
        UserDefaults.standard.string(forKey: AppStorageKey.downloadEngine)
            .flatMap(DownloadEngineKind.init(rawValue:))
            ?? .libcurl
    }
}
