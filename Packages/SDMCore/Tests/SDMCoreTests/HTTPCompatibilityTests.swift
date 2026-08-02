import Foundation
import XCTest
@testable import SDMCore

final class HTTPCompatibilityTests: XCTestCase {
    func testUnknownLengthHTMLCompletesWithMIMEInferredFilename() async throws {
        let fixture = try FixtureServer()
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))

        let snapshot = try await download(
            manager: manager,
            url: fixture.baseURL.appending(path: "github-like/pull/923"),
            destination: root.appending(path: "dynamic-html"),
            connections: 8
        )

        XCTAssertNil(snapshot.contentLength)
        XCTAssertEqual(snapshot.filename, "923.html")
        XCTAssertTrue(snapshot.segments.isEmpty)
        XCTAssertGreaterThan(snapshot.downloadedBytes, 0)
        let destinationURL = try XCTUnwrap(snapshot.destinationURL)
        XCTAssertEqual(destinationURL.lastPathComponent, "923.html")
        let contents = try String(contentsOf: destinationURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("<!doctype html>\n"))
        XCTAssertTrue(contents.contains("<title>OpenSwiftUI Pull Request 923</title>"))
        await manager.shutdown()
    }

    func testHeadFallbackNoRangeDowngradeAndRedirectMetadata() async throws {
        let fileSize = 96 * 1024
        let fixture = try FixtureServer(fileSize: fileSize)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))

        let fallback = try await download(
            manager: manager,
            url: fixture.baseURL.appending(path: "head-fallback.bin"),
            destination: root.appending(path: "fallback"),
            connections: 8
        )
        XCTAssertEqual(fallback.segments.count, 8)

        let noRange = try await download(
            manager: manager,
            url: fixture.baseURL.appending(path: "no-range.bin"),
            destination: root.appending(path: "no-range"),
            connections: 8
        )
        XCTAssertEqual(noRange.segments.count, 1)

        let redirected = try await download(
            manager: manager,
            url: fixture.baseURL.appending(path: "redirect.bin"),
            destination: root.appending(path: "redirect"),
            connections: 2
        )
        XCTAssertEqual(redirected.finalURL?.path, "/empty.bin")

        for snapshot in [fallback, noRange, redirected] {
            let destinationURL = try XCTUnwrap(snapshot.destinationURL)
            XCTAssertEqual(
                try Data(contentsOf: destinationURL),
                fixturePattern(offset: 0, length: fileSize)
            )
        }
        await manager.shutdown()
    }

    private func download(
        manager: DownloadManager,
        url: URL,
        destination: URL,
        connections: Int
    ) async throws -> DownloadSnapshot {
        let id = try await manager.enqueue(DownloadRequest(
            url: url,
            destinationDirectory: destination,
            connectionLimit: connections
        ))
        let result = try await waitForSnapshot(manager, id: id) {
            $0.state == .completed || $0.state == .failed
        }
        XCTAssertEqual(result.state, .completed, result.error?.message ?? "")
        return result
    }
}
