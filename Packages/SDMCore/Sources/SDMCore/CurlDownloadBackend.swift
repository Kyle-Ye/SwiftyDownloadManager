import Foundation
import SDMEngineBridge

/// Actor-isolated adapter for the C++/libcurl engine.
actor CurlDownloadBackend: DownloadEngineBackend {
    nonisolated let descriptor: DownloadEngineDescriptor

    private let configuration: DownloadManagerConfiguration
    private let bridge: EngineBridge
    private var pollingTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<DownloadUpdate>.Continuation] = [:]
    private var commandResults: [UInt64: UInt32] = [:]
    private var lastSequence: UInt64 = 0
    private var isShutDown = false

    init(configuration: DownloadManagerConfiguration) throws {
        guard configuration.maximumActiveDownloads > 0,
              configuration.maximumConnectionsPerDownload > 0 else {
            throw DownloadError(
                code: .invalidArgument,
                message: "Download manager limits must be positive"
            )
        }
        self.configuration = configuration
        var features: Set<DownloadFeature> = [
            .bandwidthLimiting,
            .multiConnectionTransfers,
            .persistentRecovery,
        ]
        #if os(macOS)
        features.insert(.systemTrustStore)
        #else
        features.insert(.bundledCertificateAuthorities)
        #endif
        descriptor = DownloadEngineDescriptor(
            kind: .libcurl,
            version: SDMCoreInfo.libcurlVersion,
            features: features,
            maximumConnectionsPerDownload: configuration.maximumConnectionsPerDownload
        )
        bridge = try EngineBridge(configuration: configuration)
    }

    func enqueue(_ request: DownloadRequest) async throws -> DownloadID {
        try validate(request)
        startPollingIfNeeded()
        let commandID = try bridge.enqueue(request)
        try await waitForCommand(commandID)
        return request.id
    }

    func pause(_ id: DownloadID) async throws {
        try await submit(SDM_COMMAND_PAUSE, id: id)
    }

    func resume(_ id: DownloadID) async throws {
        try await submit(SDM_COMMAND_RESUME, id: id)
    }

    func cancel(_ id: DownloadID) async throws {
        try await submit(SDM_COMMAND_CANCEL, id: id)
    }

    func retry(_ id: DownloadID) async throws {
        try await submit(SDM_COMMAND_RETRY, id: id)
    }

    func remove(_ id: DownloadID) async throws {
        try await submit(SDM_COMMAND_REMOVE, id: id)
    }

    func snapshot(for id: DownloadID) async throws -> DownloadSnapshot {
        try bridge.snapshot(for: id)
    }

    func allSnapshots() async throws -> [DownloadSnapshot] {
        try bridge.allSnapshots()
    }

    func diagnosticEvents(for id: DownloadID) async throws -> [DownloadDiagnosticEvent] {
        try bridge.diagnosticEvents(for: id)
    }

    func updates() -> AsyncStream<DownloadUpdate> {
        startPollingIfNeeded()
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[token] = continuation
            if let snapshots = try? bridge.allSnapshots(), !snapshots.isEmpty {
                continuation.yield(DownloadUpdate(
                    sequence: lastSequence,
                    snapshots: snapshots
                ))
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token) }
            }
        }
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        pollingTask?.cancel()
        pollingTask = nil
        bridge.shutdown()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        commandResults.removeAll()
    }

    private func submit(_ command: sdm_command_t, id: DownloadID) async throws {
        guard !isShutDown else {
            throw DownloadError(code: .shuttingDown, message: "Engine is shut down")
        }
        startPollingIfNeeded()
        let commandID = try bridge.submit(command, id: id)
        try await waitForCommand(commandID)
    }

    private func waitForCommand(_ commandID: UInt64) async throws {
        while !Task.isCancelled {
            try pollOnce()
            if let result = commandResults.removeValue(forKey: commandID) {
                guard result == 0 else {
                    throw DownloadError(
                        code: DownloadErrorCode(rawValue: result) ?? .internalFailure,
                        message: "Engine rejected command \(commandID)"
                    )
                }
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil, !isShutDown else { return }
        let interval = configuration.updateInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await self?.pollFromTask()
                    try await Task.sleep(for: interval)
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    private func pollFromTask() throws {
        try pollOnce()
    }

    private func pollOnce() throws {
        let events = try bridge.pollEvents()
        guard !events.isEmpty else { return }

        for event in events {
            lastSequence = max(lastSequence, event.sequence)
            if event.kind == .commandResult {
                commandResults[event.commandID] = event.result
            }
        }

        guard events.contains(where: {
            $0.kind == .snapshotChanged || $0.kind == .removed || $0.kind == .engineReady
        }) else { return }
        let update = DownloadUpdate(
            sequence: lastSequence,
            snapshots: try bridge.allSnapshots()
        )
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func removeContinuation(_ token: UUID) {
        continuations.removeValue(forKey: token)
    }

    private func validate(_ request: DownloadRequest) throws {
        guard !isShutDown else {
            throw DownloadError(code: .shuttingDown, message: "Engine is shut down")
        }
        guard let scheme = request.url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              request.url.host != nil,
              request.destinationDirectory.isFileURL,
              request.connectionLimit > 0,
              request.connectionLimit <= configuration.maximumConnectionsPerDownload else {
            throw DownloadError(
                code: .invalidArgument,
                message: "Download request is invalid"
            )
        }
    }
}
