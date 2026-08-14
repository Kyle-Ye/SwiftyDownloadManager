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
    private(set) var defaultDestinationDirectory: URL
    private(set) var defaultDownloadLocation: DefaultDownloadLocation

    let databaseURL: URL?
    let initializationError: String?

    private let manager: DownloadManager?
    private let destinationBookmarks: DestinationBookmarkStore?
    private let defaultDestinationDirectories: DefaultDownloadDestinationDirectories?
    private let userDefaults: UserDefaults
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var previousSnapshots: [DownloadID: DownloadSnapshot] = [:]

    init(
        configuration: DownloadManagerConfiguration,
        destinationDirectory: URL = FileManager.default.temporaryDirectory,
        destinationBookmarks: DestinationBookmarkStore? = nil,
        defaultDownloadLocation: DefaultDownloadLocation = .custom,
        defaultDestinationDirectories: DefaultDownloadDestinationDirectories? = nil,
        userDefaults: UserDefaults = .standard
    ) throws {
        manager = try DownloadManager(configuration: configuration)
        selectedEngine = configuration.defaultEngine
        self.destinationBookmarks = destinationBookmarks
        defaultDestinationDirectory = destinationDirectory
        self.defaultDownloadLocation = defaultDownloadLocation
        self.defaultDestinationDirectories = defaultDestinationDirectories
        self.userDefaults = userDefaults
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
        defaultDownloadLocation: DefaultDownloadLocation,
        defaultDestinationDirectories: DefaultDownloadDestinationDirectories?,
        userDefaults: UserDefaults,
        initializationError: String?,
        snapshots: [DownloadSnapshot]
    ) {
        self.manager = manager
        self.destinationBookmarks = destinationBookmarks
        defaultDestinationDirectory = destinationDirectory
        self.defaultDownloadLocation = defaultDownloadLocation
        self.defaultDestinationDirectories = defaultDestinationDirectories
        self.userDefaults = userDefaults
        self.databaseURL = databaseURL
        self.initializationError = initializationError
        selectedEngine = .libcurl
        self.snapshots = []
        isLoadingHistory = false
        startObserving()
        ingest(snapshots)
    }

    static func live(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) -> DownloadService {
        do {
            let storagePaths = try AppStoragePaths.live(fileManager: fileManager)
            let destinationBookmarks = try? DestinationBookmarkStore(
                storeURL: storagePaths.destinationBookmarksURL
            )
            #if os(macOS)
            guard let downloadsDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first else {
                throw ServiceError.unavailable(
                    "The Downloads directory could not be located."
                )
            }
            let defaultDestinationDirectories = DefaultDownloadDestinationDirectories(
                appSandbox: storagePaths.rootDirectory.appending(
                    path: "Downloads",
                    directoryHint: .isDirectory
                ),
                downloads: downloadsDirectory
            )
            var defaultDownloadLocation = storedDefaultDownloadLocation(in: userDefaults)
            let destinationDirectory: URL
            do {
                destinationDirectory = try resolveDefaultDestination(
                    location: defaultDownloadLocation,
                    customDirectory: storedCustomDefaultDestination(in: userDefaults),
                    directories: defaultDestinationDirectories,
                    destinationBookmarks: destinationBookmarks,
                    fileManager: fileManager
                )
            } catch {
                defaultDownloadLocation = .downloads
                destinationDirectory = try resolveDefaultDestination(
                    location: defaultDownloadLocation,
                    customDirectory: nil,
                    directories: defaultDestinationDirectories,
                    destinationBookmarks: destinationBookmarks,
                    fileManager: fileManager
                )
                userDefaults.set(
                    defaultDownloadLocation.rawValue,
                    forKey: AppStorageKey.defaultDownloadLocation
                )
            }
            #else
            guard let destinationDirectory = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw ServiceError.unavailable(
                    "The Documents directory could not be located."
                )
            }
            let defaultDownloadLocation = DefaultDownloadLocation.appSandbox
            let defaultDestinationDirectories: DefaultDownloadDestinationDirectories? = nil
            #endif

            return try DownloadService(
                configuration: storagePaths.managerConfiguration(
                    defaultEngine: storedEngine(in: userDefaults),
                    urlSessionIdentifier: Bundle.main.bundleIdentifier.map {
                        "\($0).urlsession-downloads"
                    }
                ),
                destinationDirectory: destinationDirectory,
                destinationBookmarks: destinationBookmarks,
                defaultDownloadLocation: defaultDownloadLocation,
                defaultDestinationDirectories: defaultDestinationDirectories,
                userDefaults: userDefaults
            )
        } catch {
            return DownloadService(
                manager: nil,
                destinationDirectory: fileManager.temporaryDirectory,
                databaseURL: nil,
                destinationBookmarks: nil,
                defaultDownloadLocation: .appSandbox,
                defaultDestinationDirectories: nil,
                userDefaults: userDefaults,
                initializationError: Self.message(for: error),
                snapshots: []
            )
        }
    }

    static func preview(
        snapshots: [DownloadSnapshot] = [],
        destinationDirectory: URL = FileManager.default.temporaryDirectory
    ) -> DownloadService {
        DownloadService(
            manager: nil,
            destinationDirectory: destinationDirectory,
            databaseURL: nil,
            destinationBookmarks: nil,
            defaultDownloadLocation: .appSandbox,
            defaultDestinationDirectories: nil,
            userDefaults: .standard,
            initializationError: nil,
            snapshots: snapshots
        )
    }

    var hasStoredCustomDefaultDestination: Bool {
        Self.storedCustomDefaultDestination(in: userDefaults) != nil
    }

    func selectDefaultDestination(
        _ location: DefaultDownloadLocation,
        customDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard let defaultDestinationDirectories else {
            throw ServiceError.unavailable(
                "Default download folder settings are unavailable on this platform."
            )
        }
        let storedCustomDirectory = Self.storedCustomDefaultDestination(in: userDefaults)
        let resolvedDirectory = try Self.resolveDefaultDestination(
            location: location,
            customDirectory: customDirectory ?? storedCustomDirectory,
            directories: defaultDestinationDirectories,
            destinationBookmarks: destinationBookmarks,
            fileManager: fileManager
        )

        if location == .custom {
            userDefaults.set(
                resolvedDirectory.path(percentEncoded: false),
                forKey: AppStorageKey.customDefaultDownloadDirectory
            )
        }
        userDefaults.set(location.rawValue, forKey: AppStorageKey.defaultDownloadLocation)
        defaultDownloadLocation = location
        defaultDestinationDirectory = resolvedDirectory
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

    private static func storedEngine(in userDefaults: UserDefaults) -> DownloadEngineKind {
        userDefaults.string(forKey: AppStorageKey.downloadEngine)
            .flatMap(DownloadEngineKind.init(rawValue:))
            ?? .libcurl
    }

    private static func storedDefaultDownloadLocation(
        in userDefaults: UserDefaults
    ) -> DefaultDownloadLocation {
        userDefaults.string(forKey: AppStorageKey.defaultDownloadLocation)
            .flatMap(DefaultDownloadLocation.init(rawValue:))
            ?? .downloads
    }

    private static func storedCustomDefaultDestination(
        in userDefaults: UserDefaults
    ) -> URL? {
        guard let path = userDefaults.string(
            forKey: AppStorageKey.customDefaultDownloadDirectory
        ), !path.isEmpty else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private static func resolveDefaultDestination(
        location: DefaultDownloadLocation,
        customDirectory: URL?,
        directories: DefaultDownloadDestinationDirectories,
        destinationBookmarks: DestinationBookmarkStore?,
        fileManager: FileManager
    ) throws -> URL {
        if let directory = directories.directory(for: location) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.standardizedFileURL
        }

        guard let customDirectory else {
            throw ServiceError.unavailable("Choose a custom download folder first.")
        }
        guard let destinationBookmarks else {
            throw ServiceError.unavailable(
                "Persistent access to custom download folders is unavailable."
            )
        }
        let authorizedDirectory = try destinationBookmarks.authorize(customDirectory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: authorizedDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ServiceError.unavailable(
                "The selected custom download folder is no longer available."
            )
        }
        return authorizedDirectory.standardizedFileURL
    }
}
