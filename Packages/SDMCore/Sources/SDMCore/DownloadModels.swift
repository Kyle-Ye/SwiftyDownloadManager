import Foundation

/// Stable UUID-backed identity persisted by the engine.
public struct DownloadID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString.lowercased()
    }
}

public enum DownloadState: UInt32, Sendable, Codable, CaseIterable {
    case created = 0
    case probing = 1
    case queued = 2
    case downloading = 3
    case pausing = 4
    case paused = 5
    case retrying = 6
    case finalizing = 7
    case completed = 8
    case failed = 9
    case cancelled = 10
}

public enum DownloadConflictPolicy: UInt32, Sendable, Codable, CaseIterable {
    case rename = 0
    case replace = 1
    case fail = 2
}

/// Immutable input used to enqueue one direct download.
public struct DownloadRequest: Sendable, Equatable {
    public let id: DownloadID
    public let url: URL
    public let destinationDirectory: URL
    public let filename: String?
    public let connectionLimit: Int
    public let bandwidthLimit: UInt64?
    public let conflictPolicy: DownloadConflictPolicy

    public init(
        id: DownloadID = DownloadID(),
        url: URL,
        destinationDirectory: URL,
        filename: String? = nil,
        connectionLimit: Int = 8,
        bandwidthLimit: UInt64? = nil,
        conflictPolicy: DownloadConflictPolicy = .rename
    ) {
        self.id = id
        self.url = url
        self.destinationDirectory = destinationDirectory
        self.filename = filename
        self.connectionLimit = connectionLimit
        self.bandwidthLimit = bandwidthLimit
        self.conflictPolicy = conflictPolicy
    }
}

/// Filesystem locations and process-wide concurrency limits for one engine.
public struct DownloadManagerConfiguration: Sendable, Equatable {
    public let databaseURL: URL
    public let temporaryDirectory: URL
    public let maximumActiveDownloads: Int
    public let maximumConnectionsPerDownload: Int
    public let updateInterval: Duration

    public init(
        databaseURL: URL,
        temporaryDirectory: URL,
        maximumActiveDownloads: Int = 2,
        maximumConnectionsPerDownload: Int = 16,
        updateInterval: Duration = .milliseconds(50)
    ) {
        self.databaseURL = databaseURL
        self.temporaryDirectory = temporaryDirectory
        self.maximumActiveDownloads = maximumActiveDownloads
        self.maximumConnectionsPerDownload = maximumConnectionsPerDownload
        self.updateInterval = updateInterval
    }
}

public struct DownloadSegmentSnapshot: Sendable, Codable, Equatable, Identifiable {
    public let ordinal: Int
    public let start: UInt64
    public let end: UInt64
    public let next: UInt64

    public var id: Int { ordinal }

    public var downloadedBytes: UInt64 {
        next > start ? next - start : 0
    }

    public var totalBytes: UInt64 {
        end >= start ? end - start + 1 : 0
    }
}

/// Immutable engine truth for presentation or diagnostics.
public struct DownloadSnapshot: Sendable, Codable, Equatable, Identifiable {
    public let id: DownloadID
    public let sourceURL: URL
    public let finalURL: URL?
    public let destinationURL: URL?
    public let filename: String
    public let state: DownloadState
    public let contentLength: UInt64?
    public let downloadedBytes: UInt64
    public let bytesPerSecond: UInt64
    public let estimatedTimeRemaining: Duration?
    public let segments: [DownloadSegmentSnapshot]
    public let error: DownloadError?
    public let updatedAt: Date

    public init(
        id: DownloadID,
        sourceURL: URL,
        finalURL: URL? = nil,
        destinationURL: URL? = nil,
        filename: String,
        state: DownloadState,
        contentLength: UInt64? = nil,
        downloadedBytes: UInt64 = 0,
        bytesPerSecond: UInt64 = 0,
        estimatedTimeRemaining: Duration? = nil,
        segments: [DownloadSegmentSnapshot] = [],
        error: DownloadError? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.finalURL = finalURL
        self.destinationURL = destinationURL
        self.filename = filename
        self.state = state
        self.contentLength = contentLength
        self.downloadedBytes = downloadedBytes
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.segments = segments
        self.error = error
        self.updatedAt = updatedAt
    }
}

public struct DownloadUpdate: Sendable, Equatable {
    public let sequence: UInt64
    public let snapshots: [DownloadSnapshot]

    public init(sequence: UInt64, snapshots: [DownloadSnapshot]) {
        self.sequence = sequence
        self.snapshots = snapshots
    }
}
