import Foundation
import XCTest
@testable import SDMCore

final class PersistenceRecoveryTests: XCTestCase {
    func testMissingPartialFileResetsProgressAndRecordsRecoveryEvent() async throws {
        let fixture = try FixtureServer(
            fileSize: 256 * 1024,
            bytesPerSecond: 32 * 1024,
            maximumConnections: 2
        )
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let partialDirectory = root.appending(path: "partial", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = DownloadManagerConfiguration(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: partialDirectory
        )
        let firstManager = try DownloadManager(configuration: configuration)
        let id = try await firstManager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 2
        ))
        _ = try await waitForSnapshot(firstManager, id: id) {
            $0.state == .downloading && $0.downloadedBytes > 0
        }
        await firstManager.shutdown()
        for file in try FileManager.default.contentsOfDirectory(
            at: partialDirectory,
            includingPropertiesForKeys: nil
        ) {
            try FileManager.default.removeItem(at: file)
        }

        let recoveredManager = try DownloadManager(configuration: configuration)
        let recovered = try await waitForSnapshot(recoveredManager, id: id) {
            $0.state == .paused && $0.downloadedBytes == 0
        }
        XCTAssertEqual(recovered.downloadedBytes, 0)
        let events = try await recoveredManager.diagnosticEvents(for: id)
        XCTAssertTrue(events.contains {
            $0.level == .warning && $0.message.contains("resumable progress was reset")
        })
        await recoveredManager.shutdown()
    }

    func testRemovingCompletedHistoryDoesNotDeleteFinalizedFile() async throws {
        let fixture = try FixtureServer(
            fileSize: 32 * 1024,
            bytesPerSecond: 0,
            maximumConnections: 2
        )
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: DownloadManagerConfiguration(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
        let id = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 2
        ))
        let completed = try await waitForSnapshot(manager, id: id) {
            $0.state == .completed || $0.state == .failed
        }
        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        let destinationURL = try XCTUnwrap(completed.destinationURL)

        try await manager.remove(id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        do {
            _ = try await manager.snapshot(for: id)
            XCTFail("Removed history should not remain queryable")
        } catch let error as DownloadError {
            XCTAssertEqual(error.code, .notFound)
        }
        await manager.shutdown()
    }

    func testRestartPreservesCompletedProgressAndTimestamp() async throws {
        let fileSize = 128 * 1024
        let fixture = try FixtureServer(
            fileSize: fileSize,
            bytesPerSecond: 0,
            maximumConnections: 4
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
        let firstManager = try DownloadManager(configuration: configuration)
        let id = try await firstManager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 4
        ))
        let completed = try await waitForSnapshot(firstManager, id: id) {
            $0.state == .completed || $0.state == .failed
        }
        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        XCTAssertEqual(completed.downloadedBytes, UInt64(fileSize))
        XCTAssertTrue(completed.segments.allSatisfy { $0.downloadedBytes == $0.totalBytes })
        XCTAssertNotNil(completed.startedAt)
        XCTAssertNotNil(completed.lastAttemptAt)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertLessThanOrEqual(completed.createdAt, completed.updatedAt)
        let completedEvents = try await firstManager.diagnosticEvents(for: id)
        XCTAssertTrue(completedEvents.contains { $0.message.contains("Completed") })
        await firstManager.shutdown()

        let recoveredManager = try DownloadManager(configuration: configuration)
        let recovered = try await waitForSnapshot(recoveredManager, id: id) {
            $0.state == .completed
        }
        XCTAssertEqual(recovered.contentLength, UInt64(fileSize))
        XCTAssertEqual(recovered.downloadedBytes, UInt64(fileSize))
        XCTAssertTrue(recovered.segments.allSatisfy { $0.downloadedBytes == $0.totalBytes })
        XCTAssertEqual(
            recovered.updatedAt.timeIntervalSince1970,
            completed.updatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        let recoveredEvents = try await recoveredManager.diagnosticEvents(for: id)
        XCTAssertEqual(recoveredEvents, completedEvents)
        await recoveredManager.shutdown()
    }

    func testRestartRestoresPausedSegmentsAndCompletesByteCorrectly() async throws {
        let fileSize = 512 * 1024
        let fixture = try FixtureServer(
            fileSize: fileSize,
            bytesPerSecond: 64 * 1024,
            maximumConnections: 4
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
        let firstManager = try DownloadManager(configuration: configuration)
        let id = try await firstManager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 4
        ))
        let partial = try await waitForSnapshot(firstManager, id: id) {
            $0.state == .downloading && $0.downloadedBytes > 0
        }
        XCTAssertLessThan(partial.downloadedBytes, UInt64(fileSize))
        await firstManager.shutdown()

        let recoveredManager = try DownloadManager(configuration: configuration)
        let recovered = try await waitForSnapshot(recoveredManager, id: id) {
            $0.state == .paused
        }
        XCTAssertEqual(recovered.segments.count, 4)
        XCTAssertGreaterThan(recovered.downloadedBytes, 0)

        try await recoveredManager.resume(id)
        let completed = try await waitForSnapshot(
            recoveredManager,
            id: id,
            timeout: .seconds(10)
        ) {
            $0.state == .completed || $0.state == .failed
        }
        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        let destinationURL = try XCTUnwrap(completed.destinationURL)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            fixturePattern(offset: 0, length: fileSize)
        )
        await recoveredManager.shutdown()
    }
}
