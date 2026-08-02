import Foundation
import Observation
import SDMCore

/// App-layer adapter that owns the engine lifecycle and publishes immutable
/// snapshots for SwiftUI. The C++ engine remains the source of download truth.
@Observable
@MainActor
final class DownloadService {
    private(set) var snapshots: [DownloadSnapshot]
    private(set) var commandInFlightIDs: Set<DownloadID> = []
    private(set) var logsByDownloadID: [DownloadID: [DownloadLogEntry]] = [:]

    let defaultDestinationDirectory: URL
    let initializationError: String?

    private let manager: DownloadManager?
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var previousSnapshots: [DownloadID: DownloadSnapshot] = [:]
    @ObservationIgnored private var lastLoggedProgressBuckets: [DownloadID: Int] = [:]

    init(
        configuration: DownloadManagerConfiguration,
        destinationDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        manager = try DownloadManager(configuration: configuration)
        defaultDestinationDirectory = destinationDirectory
        initializationError = nil
        snapshots = []
        startObserving()
    }

    private init(
        manager: DownloadManager?,
        destinationDirectory: URL,
        initializationError: String?,
        snapshots: [DownloadSnapshot]
    ) {
        self.manager = manager
        defaultDestinationDirectory = destinationDirectory
        self.initializationError = initializationError
        self.snapshots = []
        startObserving()
        ingest(snapshots)
    }

    static func live(fileManager: FileManager = .default) -> DownloadService {
        do {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = applicationSupport.appending(
                path: "SwiftyDownloadManager",
                directoryHint: .isDirectory
            )
            let temporaryDirectory = root.appending(
                path: "PartialDownloads",
                directoryHint: .isDirectory
            )
            guard let destinationDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first else {
                throw ServiceError.unavailable(
                    "The Downloads directory could not be located."
                )
            }

            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let configuration = DownloadManagerConfiguration(
                databaseURL: root.appending(path: "downloads.sqlite3"),
                temporaryDirectory: temporaryDirectory
            )
            return try DownloadService(
                configuration: configuration,
                destinationDirectory: destinationDirectory
            )
        } catch {
            return DownloadService(
                manager: nil,
                destinationDirectory: fileManager.temporaryDirectory,
                initializationError: Self.message(for: error),
                snapshots: []
            )
        }
    }

    static func preview(snapshots: [DownloadSnapshot] = []) -> DownloadService {
        DownloadService(
            manager: nil,
            destinationDirectory: FileManager.default.temporaryDirectory,
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
        let request = DownloadRequest(
            url: url,
            destinationDirectory: destinationDirectory ?? defaultDestinationDirectory,
            connectionLimit: connectionCount
        )
        appendLog(
            to: request.id,
            level: .info,
            message: "Add requested with \(connectionCount) connection(s): \(url.absoluteString)"
        )
        do {
            let id = try await manager.enqueue(request)
            appendLog(to: id, level: .info, message: "Download accepted by the engine.")
            return id
        } catch {
            appendLog(
                to: request.id,
                level: .error,
                message: "Add failed: \(Self.message(for: error))"
            )
            throw error
        }
    }

    func perform(_ command: DownloadCommand, on id: DownloadID) async throws {
        let manager = try requiredManager()
        guard commandInFlightIDs.insert(id).inserted else { return }
        defer { commandInFlightIDs.remove(id) }

        appendLog(to: id, level: .info, message: "\(command.title) requested.")
        do {
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
            appendLog(to: id, level: .info, message: "\(command.title) accepted.")
        } catch {
            appendLog(
                to: id,
                level: .error,
                message: "\(command.title) failed: \(Self.message(for: error))"
            )
            throw error
        }
    }

    func logs(for id: DownloadID) -> [DownloadLogEntry] {
        logsByDownloadID[id] ?? []
    }

    func shutdown() async {
        observationTask?.cancel()
        observationTask = nil
        if let manager {
            await manager.shutdown()
        }
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
            recordChanges(from: previousSnapshots[snapshot.id], to: snapshot)
        }
        for removedID in previousSnapshots.keys where nextByID[removedID] == nil {
            appendLog(to: removedID, level: .info, message: "Removed from download history.")
            lastLoggedProgressBuckets[removedID] = nil
        }
        previousSnapshots = nextByID
        snapshots = nextSnapshots
    }

    private func recordChanges(
        from previous: DownloadSnapshot?,
        to current: DownloadSnapshot
    ) {
        if let previous {
            if previous.state != current.state {
                appendLog(
                    to: current.id,
                    level: current.state == .failed ? .error : .info,
                    message: "State changed: \(previous.state.title) → \(current.state.title)."
                )
            }
        } else {
            appendLog(
                to: current.id,
                level: .info,
                message: "Loaded \(current.displayFilename) in state \(current.state.title)."
            )
        }

        if previous?.error != current.error, let error = current.error {
            appendLog(
                to: current.id,
                level: .error,
                message: "Engine error \(error.code.rawValue): \(error.message)"
            )
        }

        if previous?.state != .completed, current.state == .completed,
           let destinationURL = current.destinationURL {
            appendLog(
                to: current.id,
                level: .info,
                message: "Finalized at \(destinationURL.path(percentEncoded: false))."
            )
        }

        guard let progress = current.progressFraction else { return }
        let bucket = min(Int(progress * 10), 10)
        let previousBucket = lastLoggedProgressBuckets[current.id] ?? -1
        guard bucket > previousBucket else { return }
        lastLoggedProgressBuckets[current.id] = bucket
        if bucket > 0 {
            appendLog(
                to: current.id,
                level: .info,
                message: "Progress reached \(bucket * 10)%."
            )
        }
    }

    private func appendLog(
        to id: DownloadID,
        level: DownloadLogLevel,
        message: String
    ) {
        var entries = logsByDownloadID[id, default: []]
        entries.append(DownloadLogEntry(level: level, message: message))
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
        logsByDownloadID[id] = entries
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
