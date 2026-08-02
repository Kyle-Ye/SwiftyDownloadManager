import Foundation
import SDMCore
import XCTest
@testable import SDMApp

final class SDMAppTests: XCTestCase {
    func testInitialDownloadFiltersRemainStable() {
        XCTAssertEqual(DownloadFilter.allCases.count, 5)
        XCTAssertEqual(DownloadFilter.allCases.first, .all)
    }

    func testAppCanFormAnSDMCoreDownloadRequest() throws {
        let request = DownloadRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/archive.zip")),
            destinationDirectory: FileManager.default.temporaryDirectory,
            connectionLimit: 8
        )

        XCTAssertEqual(request.connectionLimit, 8)
    }

    func testFiltersClassifyDownloadStates() {
        XCTAssertTrue(DownloadFilter.downloading.includes(.probing))
        XCTAssertTrue(DownloadFilter.downloading.includes(.downloading))
        XCTAssertTrue(DownloadFilter.queued.includes(.paused))
        XCTAssertTrue(DownloadFilter.completed.includes(.completed))
        XCTAssertTrue(DownloadFilter.failed.includes(.cancelled))
        XCTAssertFalse(DownloadFilter.completed.includes(.failed))
    }

    func testCommandAvailabilityMatchesEngineStateMachine() {
        XCTAssertTrue(DownloadState.downloading.allows(.pause))
        XCTAssertTrue(DownloadState.downloading.allows(.cancel))
        XCTAssertFalse(DownloadState.downloading.allows(.retry))
        XCTAssertTrue(DownloadState.paused.allows(.resume))
        XCTAssertTrue(DownloadState.paused.allows(.remove))
        XCTAssertTrue(DownloadState.failed.allows(.retry))
        XCTAssertFalse(DownloadState.completed.allows(.cancel))
    }

    func testProgressFractionIsBounded() throws {
        let snapshot = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/file.bin")),
            filename: "file.bin",
            state: .downloading,
            contentLength: 100,
            downloadedBytes: 120
        )

        XCTAssertEqual(snapshot.progressFraction, 1)
    }

    @MainActor
    func testDownloadServiceInitializesAndShutsDown() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = try DownloadService(
            configuration: DownloadManagerConfiguration(
                databaseURL: root.appending(path: "downloads.sqlite3"),
                temporaryDirectory: root.appending(
                    path: "partial",
                    directoryHint: .isDirectory
                )
            ),
            destinationDirectory: root
        )

        XCTAssertNil(service.initializationError)
        XCTAssertTrue(service.snapshots.isEmpty)
        await service.shutdown()
    }
}
