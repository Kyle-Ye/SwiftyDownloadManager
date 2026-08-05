protocol DownloadEngineBackend: Actor {
    nonisolated var descriptor: DownloadEngineDescriptor { get }

    func enqueue(_ request: DownloadRequest) async throws -> DownloadID
    func pause(_ id: DownloadID) async throws
    func resume(_ id: DownloadID) async throws
    func cancel(_ id: DownloadID) async throws
    func retry(_ id: DownloadID) async throws
    func remove(_ id: DownloadID) async throws
    func snapshot(for id: DownloadID) async throws -> DownloadSnapshot
    func allSnapshots() async throws -> [DownloadSnapshot]
    func diagnosticEvents(for id: DownloadID) async throws -> [DownloadDiagnosticEvent]
    func updates() -> AsyncStream<DownloadUpdate>
    func shutdown() async
}
