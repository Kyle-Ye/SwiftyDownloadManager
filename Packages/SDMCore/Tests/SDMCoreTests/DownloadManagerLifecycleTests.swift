import Foundation
import XCTest
@testable import SDMCore

final class DownloadManagerLifecycleTests: XCTestCase {
    func testManagerProcessesLifecycleCommandsAndUpdates() async throws {
        let fixture = try FixtureServer(fileSize: 32 * 1024, bytesPerSecond: 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
        let request = DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 1
        )

        let updateTask = Task { () -> DownloadUpdate? in
            for await update in await manager.updates() {
                if update.snapshots.contains(where: { $0.id == request.id }) {
                    return update
                }
            }
            return nil
        }

        let id = try await manager.enqueue(request)
        XCTAssertEqual(id, request.id)
        let update = await updateTask.value
        XCTAssertNotNil(update)

        _ = try await waitForSnapshot(manager, id: id) {
            $0.state == .downloading
        }
        try await manager.pause(id)
        let pausedSnapshot = try await manager.snapshot(for: id)
        XCTAssertEqual(pausedSnapshot.state, .paused)

        try await manager.resume(id)
        let resumedSnapshot = try await manager.snapshot(for: id)
        XCTAssertTrue([.queued, .downloading].contains(resumedSnapshot.state))

        try await manager.cancel(id)
        let cancelledSnapshot = try await manager.snapshot(for: id)
        XCTAssertEqual(cancelledSnapshot.state, .cancelled)

        try await manager.retry(id)
        let retriedSnapshot = try await manager.snapshot(for: id)
        XCTAssertTrue([.queued, .downloading].contains(retriedSnapshot.state))

        try await manager.pause(id)
        try await manager.remove(id)
        let snapshots = try await manager.allSnapshots()
        XCTAssertTrue(snapshots.isEmpty)
        await manager.shutdown()
    }

    func testManagerRejectsInvalidConnectionLimit() async throws {
        let root = FileManager.default.temporaryDirectory
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "sdm-test.sqlite3"),
            temporaryDirectory: root,
            maximumConnectionsPerDownload: 4
        ))
        let request = DownloadRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1/empty.bin")),
            destinationDirectory: root,
            connectionLimit: 8
        )

        do {
            _ = try await manager.enqueue(request)
            XCTFail("Expected invalid request")
        } catch let error as DownloadError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
        await manager.shutdown()
    }
}
