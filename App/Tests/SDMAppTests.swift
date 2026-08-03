import Foundation
import SDMCore
import SwiftUI
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

    func testBrowserDownloadRequestParsesExtensionCallback() throws {
        var components = URLComponents()
        components.scheme = BrowserDownloadRequest.callbackScheme
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://example.com/archive.zip?token=a&b=2"),
            URLQueryItem(name: "filename", value: "release.zip"),
            URLQueryItem(name: "source", value: "https://example.com/releases"),
        ]

        let request = try XCTUnwrap(
            components.url.flatMap(BrowserDownloadRequest.init(callbackURL:))
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.com/archive.zip?token=a&b=2")
        XCTAssertEqual(request.suggestedFilename, "release.zip")
        XCTAssertEqual(request.sourcePageURL?.absoluteString, "https://example.com/releases")
    }

    func testBrowserDownloadRequestRejectsUntrustedRoutesAndSchemes() throws {
        let wrongRoute = try XCTUnwrap(
            URL(string: "swifty-download-manager://settings?url=https://example.com/file.zip")
        )
        var components = URLComponents()
        components.scheme = BrowserDownloadRequest.callbackScheme
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: "file:///tmp/private.txt"),
        ]

        XCTAssertNil(BrowserDownloadRequest(callbackURL: wrongRoute))
        XCTAssertNil(components.url.flatMap(BrowserDownloadRequest.init(callbackURL:)))
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

    func testMenuBarActiveStateClassification() {
        let activeStates: Set<DownloadState> = [
            .created,
            .probing,
            .queued,
            .downloading,
            .pausing,
            .paused,
            .retrying,
            .finalizing,
        ]

        for state in DownloadState.allCases {
            XCTAssertEqual(
                state.isActiveForMenuBar,
                activeStates.contains(state),
                "Unexpected menu bar classification for \(state)"
            )
        }
    }

    func testOnlyWorkingStatesUseIndeterminateMenuBarProgress() {
        let indeterminateStates: Set<DownloadState> = [
            .probing,
            .downloading,
            .retrying,
            .finalizing,
        ]

        for state in DownloadState.allCases {
            XCTAssertEqual(
                state.showsIndeterminateMenuBarProgress,
                indeterminateStates.contains(state),
                "Unexpected indeterminate progress classification for \(state)"
            )
        }
    }

    func testRecentDownloadsPrioritizeActiveAndBackfillHistory() throws {
        let activeOlder = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            state: .paused,
            createdAt: 10,
            updatedAt: 20
        )
        let activeNewer = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000002",
            state: .downloading,
            createdAt: 20,
            updatedAt: 30
        )
        let completedNewest = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000003",
            state: .completed,
            createdAt: 30,
            updatedAt: 100
        )
        let failedOlder = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000004",
            state: .failed,
            createdAt: 5,
            updatedAt: 10
        )

        let result = RecentDownloads.select(
            from: [completedNewest, activeOlder, failedOlder, activeNewer]
        )

        XCTAssertEqual(
            result.map(\.id),
            [activeNewer.id, activeOlder.id, completedNewest.id, failedOlder.id]
        )
    }

    func testRecentDownloadsUseStableOrderingForEqualUpdateTimes() throws {
        let olderCreation = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000003",
            state: .queued,
            createdAt: 10,
            updatedAt: 30
        )
        let higherID = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000002",
            state: .queued,
            createdAt: 20,
            updatedAt: 30
        )
        let lowerID = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            state: .queued,
            createdAt: 20,
            updatedAt: 30
        )

        let result = RecentDownloads.select(
            from: [olderCreation, higherID, lowerID]
        )

        XCTAssertEqual(result.map(\.id), [lowerID.id, higherID.id, olderCreation.id])
    }

    func testRecentDownloadsLimitResultsToEight() throws {
        let snapshots = try (0 ..< 10).map { index in
            try makeSnapshot(
                id: "00000000-0000-0000-0000-00000000000\(index)",
                state: .downloading,
                createdAt: TimeInterval(index),
                updatedAt: TimeInterval(index)
            )
        }

        let result = RecentDownloads.select(from: snapshots)

        XCTAssertEqual(result.count, RecentDownloads.maximumCount)
        XCTAssertEqual(
            result.map(\.updatedAt),
            (2 ... 9).reversed().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    @MainActor
    func testClosingLastWindowKeepsMenuBarApplicationRunning() {
        let delegate = SDMApplicationDelegate()

        XCTAssertFalse(
            delegate.applicationShouldTerminateAfterLastWindowClosed(.shared)
        )
    }

    @MainActor
    func testMenuBarDownloadRowsContributeIntrinsicHeight() throws {
        let snapshot = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            state: .downloading,
            createdAt: 10,
            updatedAt: 20
        )
        let hostingView = NSHostingView(
            rootView: MenuBarDownloadList(
                service: DownloadService.preview(snapshots: [snapshot])
            )
        )

        XCTAssertGreaterThan(hostingView.fittingSize.height, 70)
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

    private func makeSnapshot(
        id: String,
        state: DownloadState,
        createdAt: TimeInterval,
        updatedAt: TimeInterval
    ) throws -> DownloadSnapshot {
        DownloadSnapshot(
            id: DownloadID(rawValue: try XCTUnwrap(UUID(uuidString: id))),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/file.bin")),
            filename: "file.bin",
            state: state,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
