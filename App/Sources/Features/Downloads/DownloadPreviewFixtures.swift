#if DEBUG
import Foundation
import SDMCore

enum DownloadPreviewFixtures {
    static let segments = [
        DownloadSegmentSnapshot(
            ordinal: 0,
            start: 0,
            end: 67_108_863,
            next: 51_380_224
        ),
        DownloadSegmentSnapshot(
            ordinal: 1,
            start: 67_108_864,
            end: 134_217_727,
            next: 104_857_600
        ),
        DownloadSegmentSnapshot(
            ordinal: 2,
            start: 134_217_728,
            end: 201_326_591,
            next: 150_994_944
        ),
        DownloadSegmentSnapshot(
            ordinal: 3,
            start: 201_326_592,
            end: 268_435_455,
            next: 218_103_808
        ),
    ]

    static let downloading = DownloadSnapshot(
        id: id("00000000-0000-0000-0000-000000000001"),
        sourceURL: url("https://example.com/SwiftyDownloadManager-2.1.dmg"),
        filename: "SwiftyDownloadManager-2.1.dmg",
        state: .downloading,
        contentLength: 268_435_456,
        downloadedBytes: 64_487_424,
        bytesPerSecond: 8_388_608,
        estimatedTimeRemaining: .seconds(25),
        segments: segments,
        createdAt: referenceDate.addingTimeInterval(-600),
        startedAt: referenceDate.addingTimeInterval(-120),
        lastAttemptAt: referenceDate.addingTimeInterval(-120),
        updatedAt: referenceDate
    )

    static let paused = DownloadSnapshot(
        id: id("00000000-0000-0000-0000-000000000002"),
        sourceURL: url("https://example.com/Xcode_26.6.xip"),
        filename: "Xcode_26.6.xip",
        state: .paused,
        contentLength: 2_147_483_648,
        downloadedBytes: 912_680_550,
        createdAt: referenceDate.addingTimeInterval(-3_600),
        startedAt: referenceDate.addingTimeInterval(-3_000),
        lastAttemptAt: referenceDate.addingTimeInterval(-3_000),
        updatedAt: referenceDate.addingTimeInterval(-300)
    )

    static let completed = DownloadSnapshot(
        id: id("00000000-0000-0000-0000-000000000003"),
        sourceURL: url("https://github.com/example/LookInside-2.3.10-macOS-app.zip"),
        destinationURL: URL(filePath: "/Users/preview/Downloads/LookInside-2.3.10.zip"),
        filename: "LookInside-2.3.10-macOS-app.zip",
        state: .completed,
        contentLength: 11_534_336,
        downloadedBytes: 11_534_336,
        createdAt: referenceDate.addingTimeInterval(-7_200),
        startedAt: referenceDate.addingTimeInterval(-7_100),
        lastAttemptAt: referenceDate.addingTimeInterval(-7_100),
        completedAt: referenceDate.addingTimeInterval(-7_000),
        updatedAt: referenceDate.addingTimeInterval(-7_000)
    )

    static let failed = DownloadSnapshot(
        id: id("00000000-0000-0000-0000-000000000004"),
        sourceURL: url("https://cdn.example.com/archive-with-a-long-filename.zip"),
        filename: "archive-with-a-long-filename.zip",
        state: .failed,
        contentLength: 536_870_912,
        downloadedBytes: 25_165_824,
        createdAt: referenceDate.addingTimeInterval(-10_800),
        startedAt: referenceDate.addingTimeInterval(-10_700),
        lastAttemptAt: referenceDate.addingTimeInterval(-900),
        updatedAt: referenceDate.addingTimeInterval(-850)
    )

    static let snapshots = [downloading, paused, completed, failed]

    static let diagnosticEvents = [
        DownloadDiagnosticEvent(
            id: 1,
            timestamp: referenceDate.addingTimeInterval(-12),
            level: .info,
            message: "Connected to example.com using HTTP/2"
        ),
        DownloadDiagnosticEvent(
            id: 2,
            timestamp: referenceDate.addingTimeInterval(-7),
            level: .warning,
            message: "Connection 3 slowed down; rebalancing remaining ranges"
        ),
        DownloadDiagnosticEvent(
            id: 3,
            timestamp: referenceDate,
            level: .error,
            code: 28,
            message: "The transfer timed out"
        ),
    ]

    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 807_840_000)

    private static func id(_ value: String) -> DownloadID {
        DownloadID(rawValue: UUID(uuidString: value)!)
    }

    private static func url(_ value: String) -> URL {
        URL(string: value)!
    }
}
#endif
