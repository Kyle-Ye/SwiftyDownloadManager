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
public struct DownloadRequest: Sendable, Codable, Equatable {
    public let id: DownloadID
    public let url: URL
    public let destinationDirectory: URL
    public let filename: String?
    public let connectionLimit: Int
    public let bandwidthLimit: UInt64?
    public let conflictPolicy: DownloadConflictPolicy
    public let requestContext: DownloadRequestContext?
    public let requiresRequestContext: Bool
    public let rejectsHTML: Bool

    public init(
        id: DownloadID = DownloadID(),
        url: URL,
        destinationDirectory: URL,
        filename: String? = nil,
        connectionLimit: Int = 8,
        bandwidthLimit: UInt64? = nil,
        conflictPolicy: DownloadConflictPolicy = .rename,
        requestContext: DownloadRequestContext? = nil,
        rejectsHTML: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.destinationDirectory = destinationDirectory
        self.filename = filename
        self.connectionLimit = connectionLimit
        self.bandwidthLimit = bandwidthLimit
        self.conflictPolicy = conflictPolicy
        self.requestContext = requestContext
        requiresRequestContext = requestContext != nil
        self.rejectsHTML = rejectsHTML ?? Self.expectsFile(url: url, filename: filename)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, destinationDirectory, filename, connectionLimit, bandwidthLimit, conflictPolicy
        case requiresRequestContext, rejectsHTML
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(DownloadID.self, forKey: .id)
        url = try values.decode(URL.self, forKey: .url)
        destinationDirectory = try values.decode(URL.self, forKey: .destinationDirectory)
        filename = try values.decodeIfPresent(String.self, forKey: .filename)
        connectionLimit = try values.decode(Int.self, forKey: .connectionLimit)
        bandwidthLimit = try values.decodeIfPresent(UInt64.self, forKey: .bandwidthLimit)
        conflictPolicy = try values.decode(DownloadConflictPolicy.self, forKey: .conflictPolicy)
        requiresRequestContext = try values.decodeIfPresent(Bool.self, forKey: .requiresRequestContext) ?? false
        rejectsHTML = try values.decodeIfPresent(Bool.self, forKey: .rejectsHTML)
            ?? Self.expectsFile(url: url, filename: filename)
        requestContext = nil
    }

    static func expectsFile(url: URL, filename: String?) -> Bool {
        let name = filename.map { URL(fileURLWithPath: $0) } ?? url
        return Set("7z apk avi bin bz2 cab dmg doc docx exe flac gz img iso jar m4a m4v mkv mov mp3 mp4 msi ods odt pdf pkg ppt pptx rar tar tgz wav webm xls xlsx xip xz zip zipx".split(separator: " "))
            .contains(Substring(name.pathExtension.lowercased()))
    }

    func validateContext() throws {
        guard !requiresRequestContext || requestContext != nil else {
            throw DownloadError(code: .invalidState, message: Self.missingContextMessage)
        }
        try requestContext?.validate(for: url)
    }

    static let missingContextMessage = "The browser session is no longer available. Sign in and send this download from the browser again."
    static let unexpectedHTMLMessage = "The server returned a web page instead of the file. Sign in and send this download from the browser again."
}

/// Filesystem locations and process-wide concurrency limits for one engine.
public struct DownloadManagerConfiguration: Sendable, Equatable {
    public let databaseURL: URL
    public let temporaryDirectory: URL
    public let maximumActiveDownloads: Int
    public let maximumConnectionsPerDownload: Int
    public let updateInterval: Duration
    public let defaultEngine: DownloadEngineKind
    public let urlSessionIdentifier: String?

    public init(
        databaseURL: URL,
        temporaryDirectory: URL,
        maximumActiveDownloads: Int = 2,
        maximumConnectionsPerDownload: Int = 16,
        updateInterval: Duration = .milliseconds(50),
        defaultEngine: DownloadEngineKind = .libcurl,
        urlSessionIdentifier: String? = nil
    ) {
        self.databaseURL = databaseURL
        self.temporaryDirectory = temporaryDirectory
        self.maximumActiveDownloads = maximumActiveDownloads
        self.maximumConnectionsPerDownload = maximumConnectionsPerDownload
        self.updateInterval = updateInterval
        self.defaultEngine = defaultEngine
        self.urlSessionIdentifier = urlSessionIdentifier
    }
}

public struct DownloadSegmentSnapshot: Sendable, Codable, Equatable, Identifiable {
    public let ordinal: Int
    public let start: UInt64
    public let end: UInt64
    public let next: UInt64

    public init(ordinal: Int, start: UInt64, end: UInt64, next: UInt64) {
        self.ordinal = ordinal
        self.start = start
        self.end = end
        self.next = next
    }

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
    public let createdAt: Date
    public let startedAt: Date?
    public let lastAttemptAt: Date?
    public let completedAt: Date?
    public let updatedAt: Date
    public let engine: DownloadEngineKind

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
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date = .now,
        engine: DownloadEngineKind = .libcurl
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
        self.createdAt = createdAt ?? updatedAt
        self.startedAt = startedAt
        self.lastAttemptAt = lastAttemptAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.engine = engine
    }
}

public enum DownloadDiagnosticLevel: UInt32, Sendable, Codable, CaseIterable {
    case info = 0
    case warning = 1
    case error = 2
}

public struct DownloadDiagnosticEvent: Sendable, Codable, Equatable, Identifiable {
    public let id: UInt64
    public let timestamp: Date
    public let level: DownloadDiagnosticLevel
    public let code: UInt32
    public let message: String

    public init(
        id: UInt64,
        timestamp: Date,
        level: DownloadDiagnosticLevel,
        code: UInt32 = 0,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.code = code
        self.message = message
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
