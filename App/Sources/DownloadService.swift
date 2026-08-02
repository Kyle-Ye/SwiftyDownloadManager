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

    let defaultDestinationDirectory: URL
    let initializationError: String?

    private let manager: DownloadManager?
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

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
        self.snapshots = snapshots
        startObserving()
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
        return try await manager.enqueue(DownloadRequest(
            url: url,
            destinationDirectory: destinationDirectory ?? defaultDestinationDirectory,
            connectionLimit: connectionCount
        ))
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
                self?.snapshots = update.snapshots
            }
        }
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
