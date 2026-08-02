import Foundation
import XCTest
@testable import SDMCore

final class SchedulingAndRetryTests: XCTestCase {
    func testBandwidthLimitIsAppliedAcrossAllSegments() async throws {
        let fileSize = 512 * 1024
        let bandwidthLimit = 128 * 1024
        let fixture = try FixtureServer(fileSize: fileSize)
        defer { fixture.stop() }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try makeManager(root: root)

        let clock = ContinuousClock()
        let started = clock.now
        let id = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 4,
            bandwidthLimit: UInt64(bandwidthLimit)
        ))
        let completed = try await waitForSnapshot(
            manager,
            id: id,
            timeout: .seconds(8)
        ) {
            $0.state == .completed || $0.state == .failed
        }
        let elapsed = started.duration(to: clock.now)

        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(2_500))
        XCTAssertLessThan(elapsed, .seconds(7))
        await manager.shutdown()
    }

    func testRetryableHTTPFailureUsesBackoffThenCompletes() async throws {
        let fixture = try FixtureServer(fileSize: 32 * 1024)
        defer { fixture.stop() }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try makeManager(root: root)
        let clock = ContinuousClock()
        let started = clock.now

        let id = try await manager.enqueue(DownloadRequest(
            url: fixture.baseURL.appending(path: "flaky-once.bin"),
            destinationDirectory: root,
            connectionLimit: 1
        ))
        let completed = try await waitForSnapshot(manager, id: id) {
            $0.state == .completed || $0.state == .failed
        }

        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .milliseconds(200))
        let destinationURL = try XCTUnwrap(completed.destinationURL)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            fixturePattern(offset: 0, length: 32 * 1024)
        )
        await manager.shutdown()
    }

    func testActiveDownloadLimitQueuesInEnqueueOrder() async throws {
        let fixture = try FixtureServer(fileSize: 128 * 1024, bytesPerSecond: 32 * 1024)
        defer { fixture.stop() }
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory),
            maximumActiveDownloads: 1
        ))

        let first = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root.appending(path: "first"),
            connectionLimit: 1
        ))
        _ = try await waitForSnapshot(manager, id: first) { $0.state == .downloading }
        let second = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root.appending(path: "second"),
            connectionLimit: 1
        ))
        let queued = try await manager.snapshot(for: second)
        XCTAssertEqual(queued.state, .queued)

        try await manager.cancel(first)
        _ = try await waitForSnapshot(manager, id: second) { $0.state == .downloading }
        try await manager.cancel(second)
        await manager.shutdown()
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeManager(root: URL) throws -> DownloadManager {
        try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
    }
}
