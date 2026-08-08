import Foundation
import XCTest
@testable import SDMCore

final class SegmentedDownloadTests: XCTestCase {
    func testTwoFourAndEightConnectionDownloadsAreByteCorrect() async throws {
        let fileSize = 256 * 1024
        let fixture = try FixtureServer(
            fileSize: fileSize,
            maximumConcurrentTransfers: 8
        )
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))

        for connectionCount in [2, 4, 8] {
            let destination = root.appending(
                path: "connections-\(connectionCount)",
                directoryHint: .isDirectory
            )
            let id = try await manager.enqueue(DownloadRequest(
                url: fixture.fileURL,
                destinationDirectory: destination,
                connectionLimit: connectionCount
            ))
            let completed = try await waitForSnapshot(manager, id: id) {
                $0.state == .completed || $0.state == .failed
            }

            XCTAssertEqual(
                completed.state,
                .completed,
                "\(connectionCount) connections: \(completed.error?.message ?? "")"
            )
            XCTAssertEqual(completed.segments.count, connectionCount)
            XCTAssertEqual(completed.downloadedBytes, UInt64(fileSize))
            let destinationURL = try XCTUnwrap(completed.destinationURL)
            XCTAssertEqual(
                try Data(contentsOf: destinationURL),
                fixturePattern(offset: 0, length: fileSize)
            )
        }
        await manager.shutdown()
    }

    func testIdleConnectionSplitsLargestRemainingRange() async throws {
        let fileSize = 8 * 1024 * 1024
        let fixture = try FixtureServer(
            fileSize: fileSize,
            bytesPerSecond: 8 * 1024 * 1024,
            maximumConcurrentTransfers: 2,
            slowInitialRangeBytesPerSecond: 256 * 1024
        )
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = DownloadManagerConfiguration(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        )
        let manager = try DownloadManager(configuration: configuration)
        let id = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root.appending(path: "adaptive", directoryHint: .isDirectory),
            connectionLimit: 2
        ))
        let rebalanced = try await waitForSnapshot(
            manager,
            id: id,
            timeout: .seconds(12)
        ) {
            $0.state == .downloading && $0.segments.count > 2
        }
        XCTAssertGreaterThan(rebalanced.downloadedBytes, 0)
        await manager.shutdown()

        let recoveredManager = try DownloadManager(configuration: configuration)
        let recovered = try await waitForSnapshot(recoveredManager, id: id) {
            $0.state == .paused
        }
        XCTAssertGreaterThan(recovered.segments.count, 2)
        XCTAssertGreaterThanOrEqual(recovered.downloadedBytes, rebalanced.downloadedBytes)

        try await recoveredManager.resume(id)
        let completed = try await waitForSnapshot(
            recoveredManager,
            id: id,
            timeout: .seconds(12)
        ) {
            $0.state == .completed || $0.state == .failed
        }

        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        XCTAssertGreaterThan(completed.segments.count, 2)
        XCTAssertTrue(completed.segments.allSatisfy {
            $0.downloadedBytes == $0.totalBytes
        })

        let orderedSegments = completed.segments.sorted { $0.start < $1.start }
        var expectedStart: UInt64 = 0
        for segment in orderedSegments {
            XCTAssertEqual(segment.start, expectedStart)
            expectedStart = segment.end + 1
        }
        XCTAssertEqual(expectedStart, UInt64(fileSize))

        let destinationURL = try XCTUnwrap(completed.destinationURL)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            fixturePattern(offset: 0, length: fileSize)
        )
        let events = try await recoveredManager.diagnosticEvents(for: id)
        XCTAssertTrue(events.contains {
            $0.message.contains("Reused an idle connection by splitting Range segment")
        })
        await recoveredManager.shutdown()
    }
}
