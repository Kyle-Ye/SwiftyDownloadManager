import Foundation

/// Swift-facing facade that isolates callers from concrete transport engines.
///
/// Both engines stay available for the manager lifetime. Changing the default
/// only affects newly enqueued downloads; existing downloads continue on the
/// engine that owns their persistent state.
public actor DownloadManager {
    private let backends: [DownloadEngineKind: any DownloadEngineBackend]
    private var defaultEngine: DownloadEngineKind
    private var ownerByDownloadID: [DownloadID: DownloadEngineKind] = [:]
    private var snapshotsByEngine: [DownloadEngineKind: [DownloadSnapshot]] = [:]
    private var continuations: [UUID: AsyncStream<DownloadUpdate>.Continuation] = [:]
    private var observationTasks: [DownloadEngineKind: Task<Void, Never>] = [:]
    private var sequence: UInt64 = 0
    private var isShutDown = false

    public init(configuration: DownloadManagerConfiguration) throws {
        let curl = try CurlDownloadBackend(configuration: configuration)
        let urlSession = try URLSessionDownloadBackend(configuration: configuration)
        backends = [
            .libcurl: curl,
            .urlSession: urlSession,
        ]
        defaultEngine = configuration.defaultEngine
    }

    public func engineDescriptors() -> [DownloadEngineDescriptor] {
        DownloadEngineKind.allCases.compactMap { backends[$0]?.descriptor }
    }

    public func selectedEngine() -> DownloadEngineKind {
        defaultEngine
    }

    public func setDefaultEngine(_ engine: DownloadEngineKind) throws {
        guard backends[engine] != nil else {
            throw DownloadError(
                code: .invalidArgument,
                message: "The selected download engine is unavailable."
            )
        }
        defaultEngine = engine
    }

    public func enqueue(
        _ request: DownloadRequest,
        using engine: DownloadEngineKind? = nil
    ) async throws -> DownloadID {
        try ensureRunning()
        let selectedEngine = engine ?? defaultEngine
        guard let backend = backends[selectedEngine] else {
            throw DownloadError(
                code: .invalidArgument,
                message: "The selected download engine is unavailable."
            )
        }
        try await ensureUnique(request.id)
        let id = try await backend.enqueue(request)
        ownerByDownloadID[id] = selectedEngine
        return id
    }

    public func pause(_ id: DownloadID) async throws {
        try await backend(for: id).pause(id)
    }

    public func resume(_ id: DownloadID) async throws {
        try await backend(for: id).resume(id)
    }

    public func cancel(_ id: DownloadID) async throws {
        try await backend(for: id).cancel(id)
    }

    public func retry(_ id: DownloadID) async throws {
        try await backend(for: id).retry(id)
    }

    public func remove(_ id: DownloadID) async throws {
        let owner = try await ownerKind(for: id)
        guard let backend = backends[owner] else {
            throw DownloadError(code: .notFound, message: "Download was not found")
        }
        try await backend.remove(id)
        ownerByDownloadID[id] = nil
    }

    public func snapshot(for id: DownloadID) async throws -> DownloadSnapshot {
        try await backend(for: id).snapshot(for: id)
    }

    public func allSnapshots() async throws -> [DownloadSnapshot] {
        try ensureRunning()
        var result: [DownloadSnapshot] = []
        for kind in DownloadEngineKind.allCases {
            guard let backend = backends[kind] else { continue }
            let snapshots = try await backend.allSnapshots()
            for snapshot in snapshots {
                ownerByDownloadID[snapshot.id] = kind
            }
            result.append(contentsOf: snapshots)
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func diagnosticEvents(for id: DownloadID) async throws -> [DownloadDiagnosticEvent] {
        try await backend(for: id).diagnosticEvents(for: id)
    }

    public func updates() -> AsyncStream<DownloadUpdate> {
        startObservingIfNeeded()
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[token] = continuation
            Task { [weak self] in
                await self?.broadcastCurrentSnapshots()
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token) }
            }
        }
    }

    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        for task in observationTasks.values {
            task.cancel()
        }
        observationTasks.removeAll()
        for backend in backends.values {
            await backend.shutdown()
        }
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func backend(for id: DownloadID) async throws -> any DownloadEngineBackend {
        let kind = try await ownerKind(for: id)
        guard let backend = backends[kind] else {
            throw DownloadError(code: .notFound, message: "Download was not found")
        }
        return backend
    }

    private func ownerKind(for id: DownloadID) async throws -> DownloadEngineKind {
        try ensureRunning()
        if let owner = ownerByDownloadID[id] {
            return owner
        }
        for kind in DownloadEngineKind.allCases {
            guard let backend = backends[kind] else { continue }
            do {
                _ = try await backend.snapshot(for: id)
                ownerByDownloadID[id] = kind
                return kind
            } catch let error as DownloadError where error.code == .notFound {
                continue
            }
        }
        throw DownloadError(code: .notFound, message: "Download was not found")
    }

    private func ensureUnique(_ id: DownloadID) async throws {
        for backend in backends.values {
            do {
                _ = try await backend.snapshot(for: id)
                throw DownloadError(
                    code: .invalidArgument,
                    message: "Download ID already exists"
                )
            } catch let error as DownloadError where error.code == .notFound {
                continue
            }
        }
    }

    private func startObservingIfNeeded() {
        guard observationTasks.isEmpty, !isShutDown else { return }
        for (kind, backend) in backends {
            observationTasks[kind] = Task { [weak self] in
                let stream = await backend.updates()
                for await update in stream {
                    guard !Task.isCancelled else { return }
                    await self?.ingest(update.snapshots, from: kind)
                }
            }
        }
    }

    private func ingest(
        _ snapshots: [DownloadSnapshot],
        from engine: DownloadEngineKind
    ) {
        snapshotsByEngine[engine] = snapshots
        for snapshot in snapshots {
            ownerByDownloadID[snapshot.id] = engine
        }
        broadcastCachedSnapshots()
    }

    private func broadcastCurrentSnapshots() async {
        for kind in DownloadEngineKind.allCases {
            guard let backend = backends[kind],
                  let snapshots = try? await backend.allSnapshots() else { continue }
            snapshotsByEngine[kind] = snapshots
            for snapshot in snapshots {
                ownerByDownloadID[snapshot.id] = kind
            }
        }
        broadcastCachedSnapshots()
    }

    private func broadcastCachedSnapshots() {
        sequence &+= 1
        let snapshots = snapshotsByEngine.values
            .flatMap { $0 }
            .sorted { $0.updatedAt > $1.updatedAt }
        let update = DownloadUpdate(sequence: sequence, snapshots: snapshots)
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func removeContinuation(_ token: UUID) {
        continuations[token] = nil
    }

    private func ensureRunning() throws {
        guard !isShutDown else {
            throw DownloadError(code: .shuttingDown, message: "Download manager is shut down")
        }
    }
}
