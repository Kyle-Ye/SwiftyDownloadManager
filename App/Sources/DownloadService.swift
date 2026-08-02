import Foundation
import SDMCore

/// Thin app-layer adapter. Presentation state stays in SwiftUI while all
/// download truth and work remain owned by `DownloadManager`.
@MainActor
final class DownloadService {
    private let manager: DownloadManager

    init(configuration: DownloadManagerConfiguration) throws {
        manager = try DownloadManager(configuration: configuration)
    }

    func enqueue(
        url: URL,
        destinationDirectory: URL,
        connectionCount: Int
    ) async throws -> DownloadID {
        try await manager.enqueue(DownloadRequest(
            url: url,
            destinationDirectory: destinationDirectory,
            connectionLimit: connectionCount
        ))
    }

    func observe(
        _ receive: @escaping @MainActor @Sendable ([DownloadSnapshot]) -> Void
    ) -> Task<Void, Never> {
        Task { [manager] in
            for await update in await manager.updates() {
                receive(update.snapshots)
            }
        }
    }

    func shutdown() async {
        await manager.shutdown()
    }
}
