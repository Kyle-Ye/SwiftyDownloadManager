import Foundation
import XCTest
@testable import SDMCore

final class PersistenceRecoveryTests: XCTestCase {
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
