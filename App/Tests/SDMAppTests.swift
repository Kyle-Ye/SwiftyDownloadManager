import Foundation
import SDMCore
import XCTest
@testable import SDMApp

final class SDMAppTests: XCTestCase {
    @MainActor
    func testDestinationBookmarkStorePersistsAndRestoresFolderReference() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let destination = root.appending(path: "Destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "destination-bookmarks.plist")

        let firstStore = try DestinationBookmarkStore(storeURL: storeURL)
        XCTAssertEqual(try firstStore.authorize(destination), destination.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        firstStore.stopAllAccess()

        let restoredStore = try DestinationBookmarkStore(storeURL: storeURL)
        restoredStore.stopAllAccess()
    }

    func testAppStoragePathsStayUnderInjectedApplicationSupportDirectory() throws {
        let applicationSupport = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: applicationSupport) }

        let paths = try AppStoragePaths.resolving(
            applicationSupportDirectory: applicationSupport
        )

        XCTAssertEqual(
            paths.rootDirectory,
            applicationSupport.appending(
                path: AppStoragePaths.directoryName,
                directoryHint: .isDirectory
            )
        )
        XCTAssertEqual(paths.databaseURL.lastPathComponent, "downloads.sqlite3")
        XCTAssertEqual(
            paths.destinationBookmarksURL.lastPathComponent,
            "destination-bookmarks.plist"
        )
        XCTAssertEqual(
            paths.destinationBookmarksURL.deletingLastPathComponent(),
            paths.rootDirectory
        )
        XCTAssertEqual(paths.databaseURL.deletingLastPathComponent(), paths.rootDirectory)
        XCTAssertEqual(
            paths.partialDownloadsDirectory.deletingLastPathComponent(),
            paths.rootDirectory
        )
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.partialDownloadsDirectory.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

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

    func testCompletedProgressIsFullWhenPersistedByteCountIsStale() throws {
        let knownLength = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/file.bin")),
            filename: "file.bin",
            state: .completed,
            contentLength: 100,
            downloadedBytes: 0
        )
        let unknownLength = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/page")),
            filename: "page.html",
            state: .completed,
            downloadedBytes: 100
        )

        XCTAssertEqual(knownLength.progressFraction, 1)
        XCTAssertEqual(unknownLength.progressFraction, 1)
    }

    func testDisplayFilenameUsesFinalDestinationName() throws {
        let snapshot = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/empty.bin")),
            destinationURL: URL(fileURLWithPath: "/tmp/empty (2).bin"),
            filename: "empty.bin",
            state: .completed
        )

        XCTAssertEqual(snapshot.displayFilename, "empty (2).bin")
    }

    func testInfoSectionsRemainStable() {
        XCTAssertEqual(
            DownloadInfoSection.allCases,
            [.overview, .connections, .log]
        )
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
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while service.isLoadingHistory, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(service.isLoadingHistory)
        await service.shutdown()
    }
}
