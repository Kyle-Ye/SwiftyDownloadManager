import Foundation
import Observation
import SDMCore

/// App-layer adapter that owns the engine lifecycle and publishes immutable
/// snapshots for SwiftUI. The C++ engine remains the source of download truth.
@Observable
@MainActor
final class DownloadService {
    private(set) var snapshots: [DownloadSnapshot]
    private(set) var isLoadingHistory: Bool
    private(set) var commandInFlightIDs: Set<DownloadID> = []
    private(set) var logsByDownloadID: [DownloadID: [DownloadDiagnosticEvent]] = [:]

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
        self.destinationBookmarks = destinationBookmarks
        defaultDestinationDirectory = destinationDirectory
        databaseURL = configuration.databaseURL
        initializationError = nil
        snapshots = []
        isLoadingHistory = true
        startObserving()
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
            guard let destinationDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first else {
                throw ServiceError.unavailable(
                    "The Downloads directory could not be located."
                )
            }

            return try DownloadService(
                configuration: storagePaths.managerConfiguration,
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
            connectionLimit: connectionCount
        )
        return try await manager.enqueue(request)
    }

    func perform(_ command: DownloadCommand, on id: DownloadID) async throws {
        let manager = try requiredManager()
        guard commandInFlightIDs.insert(id).inserted else { return }
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
}
