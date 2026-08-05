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
}
