import Foundation

extension DownloadSnapshot {
    func replacing(
        finalURL: URL?? = nil,
        destinationURL: URL?? = nil,
        filename: String? = nil,
        state: DownloadState? = nil,
        contentLength: UInt64?? = nil,
        downloadedBytes: UInt64? = nil,
        bytesPerSecond: UInt64? = nil,
        estimatedTimeRemaining: Duration?? = nil,
        error: DownloadError?? = nil,
        startedAt: Date?? = nil,
        lastAttemptAt: Date?? = nil,
        completedAt: Date?? = nil,
        updatedAt: Date = .now
    ) -> DownloadSnapshot {
        DownloadSnapshot(
            id: id,
            sourceURL: sourceURL,
            finalURL: finalURL ?? self.finalURL,
            destinationURL: destinationURL ?? self.destinationURL,
            filename: filename ?? self.filename,
            state: state ?? self.state,
            contentLength: contentLength ?? self.contentLength,
            downloadedBytes: downloadedBytes ?? self.downloadedBytes,
            bytesPerSecond: bytesPerSecond ?? self.bytesPerSecond,
            estimatedTimeRemaining: estimatedTimeRemaining ?? self.estimatedTimeRemaining,
            segments: segments,
            error: error ?? self.error,
            createdAt: createdAt,
            startedAt: startedAt ?? self.startedAt,
            lastAttemptAt: lastAttemptAt ?? self.lastAttemptAt,
            completedAt: completedAt ?? self.completedAt,
            updatedAt: updatedAt,
            engine: engine
        )
    }
}
