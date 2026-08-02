import Foundation
import XCTest
@testable import SDMCore

final class SingleConnectionDownloadTests: XCTestCase {
    func testSingleConnectionDownloadIsByteCorrectAndFinalizedAtomically() async throws {
        let fixture = try FixtureServer(fileSize: 64 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
        let id = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 1
        ))
        let completed = try await waitForSnapshot(manager, id: id) {
            $0.state == .completed || $0.state == .failed
        }

        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        XCTAssertEqual(completed.contentLength, 64 * 1024)
        XCTAssertEqual(completed.downloadedBytes, 64 * 1024)
        XCTAssertEqual(completed.segments.count, 1)
        let destinationURL = try XCTUnwrap(completed.destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL), fixturePattern(offset: 0, length: 64 * 1024))

        let partialDirectory = root.appending(path: "partial", directoryHint: .isDirectory)
        let partialFiles = try FileManager.default.contentsOfDirectory(
            at: partialDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(partialFiles.isEmpty)
        await manager.shutdown()
    }
}
