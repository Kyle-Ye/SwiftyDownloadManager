import Foundation
import SDMCore
import SwiftUI
import XCTest
@testable import SDMApp

final class SDMAppTests: XCTestCase {
    @MainActor
    func testSafariExtensionStateLookupReturnsAcrossTheXPCBoundary() async {
        _ = await SafariExtensionSupport.isEnabled()
    }

    func testSafariExtensionPackagesDirectNavigationCaptureResources() throws {
        let testBundleURL = Bundle(for: type(of: self)).bundleURL
        let plugInsURL = testBundleURL.deletingLastPathComponent()
        let extensionURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: plugInsURL,
                includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "appex" }
        )
        let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
        let manifestURL = try XCTUnwrap(
            extensionBundle.url(forResource: "manifest", withExtension: "json")
        )
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let background = try XCTUnwrap(manifest["background"] as? [String: Any])
        let permissions = try XCTUnwrap(manifest["permissions"] as? [String])
        let backgroundScripts = try XCTUnwrap(background["scripts"] as? [String])
        let contentScripts = try XCTUnwrap(
            manifest["content_scripts"] as? [[String: Any]]
        )
        let resourceURL = try XCTUnwrap(extensionBundle.resourceURL)

        XCTAssertEqual(background["persistent"] as? Bool, false)
        XCTAssertTrue(permissions.contains("webNavigation"))
        let packagedScripts = Set(
            backgroundScripts + contentScripts.flatMap { contentScript in
                contentScript["js"] as? [String] ?? []
            }
        )
        for script in packagedScripts {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: resourceURL.appending(path: script).path
                ),
                "Missing Safari Web Extension resource: \(script)"
            )
        }
        XCTAssertNotNil(
            extensionBundle.url(
                forResource: "capture",
                withExtension: "html",
                subdirectory: "Shared"
            )
        )
        XCTAssertNotNil(
            extensionBundle.url(
                forResource: "capture",
                withExtension: "css",
                subdirectory: "Shared"
            )
        )
        XCTAssertNotNil(
            extensionBundle.url(
                forResource: "capture",
                withExtension: "js",
                subdirectory: "Shared"
            )
        )
    }

    #if os(macOS)
    func testChromeExtensionStoreLinkUsesAssignedItemURL() throws {
        let url = try XCTUnwrap(ChromeExtensionSupport.webStoreURL)

        XCTAssertEqual(
            url.absoluteString,
            "https://chromewebstore.google.com/detail/jjhjgmnpneldikhkejhoeonjpbbekbpg"
        )
    }
    #endif

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
        XCTAssertEqual(
            try firstStore.authorize(destination, owner: "test"),
            destination.standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        try firstStore.release(owner: "test")
        firstStore.stopAllAccess()

        let releasedRecords = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: storeURL),
                format: nil
            ) as? [[String: Any]]
        )
        XCTAssertTrue(releasedRecords.isEmpty)

        let restoredStore = try DestinationBookmarkStore(storeURL: storeURL)
        restoredStore.stopAllAccess()
    }

    @MainActor
    func testDestinationBookmarkStoreRetainsSavedDefaultWithoutAnOwner() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let destination = root.appending(path: "Destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "destination-bookmarks.plist")

        let firstStore = try DestinationBookmarkStore(storeURL: storeURL)
        _ = try firstStore.authorize(
            destination,
            owner: "default",
            retainBookmarkWhenUnowned: true
        )
        try firstStore.release(
            owner: "default",
            retainBookmarkWhenUnowned: true
        )
        firstStore.stopAllAccess()

        let releasedRecords = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: storeURL),
                format: nil
            ) as? [[String: Any]]
        )
        XCTAssertEqual(releasedRecords.count, 1)
        XCTAssertEqual(releasedRecords.first?["owners"] as? [String], [])
        XCTAssertEqual(
            releasedRecords.first?["retainsBookmarkWhenUnowned"] as? Bool,
            true
        )

        let restoredStore = try DestinationBookmarkStore(storeURL: storeURL)
        XCTAssertEqual(
            try restoredStore.authorize(
                destination,
                owner: "default",
                retainBookmarkWhenUnowned: true
            ),
            destination.standardizedFileURL
        )
        restoredStore.stopAllAccess()
    }

    #if os(macOS)
    @MainActor
    func testDefaultDownloadDestinationSelectionPersistsAndCreatesFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
        let appSandbox = root.appending(path: "AppData", directoryHint: .isDirectory)
        let custom = root.appending(path: "Custom", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "SDMAppTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let bookmarks = try DestinationBookmarkStore(
            storeURL: root.appending(path: "destination-bookmarks.plist")
        )
        let directories = DefaultDownloadDestinationDirectories(
            appSandbox: appSandbox,
            downloads: downloads
        )
        let service = try DownloadService(
            configuration: DownloadManagerConfiguration(
                databaseURL: root.appending(path: "downloads.sqlite3"),
                temporaryDirectory: root.appending(
                    path: "PartialDownloads",
                    directoryHint: .isDirectory
                )
            ),
            destinationDirectory: downloads,
            destinationBookmarks: bookmarks,
            defaultDownloadLocation: .downloads,
            defaultDestinationDirectories: directories,
            userDefaults: userDefaults
        )

        try service.selectDefaultDestination(.appSandbox)
        XCTAssertEqual(service.defaultDownloadLocation, .appSandbox)
        XCTAssertEqual(service.defaultDestinationDirectory, appSandbox.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSandbox.path))

        try service.selectDefaultDestination(.downloadsSDM)
        let downloadsSDM = try XCTUnwrap(directories.downloadsSDM)
        XCTAssertEqual(service.defaultDestinationDirectory, downloadsSDM)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadsSDM.path))

        try service.selectDefaultDestination(.custom, customDirectory: custom)
        XCTAssertEqual(service.defaultDownloadLocation, .custom)
        XCTAssertEqual(service.defaultDestinationDirectory, custom.standardizedFileURL)
        XCTAssertEqual(
            userDefaults.string(forKey: AppStorageKey.defaultDownloadLocation),
            DefaultDownloadLocation.custom.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppStorageKey.customDefaultDownloadDirectory),
            custom.path(percentEncoded: false)
        )

        await service.shutdown()
    }

    func testDefaultDownloadDestinationDirectoryMapping() {
        let directories = DefaultDownloadDestinationDirectories(
            appSandbox: URL(filePath: "/AppData/Downloads", directoryHint: .isDirectory),
            downloads: URL(filePath: "/Users/example/Downloads", directoryHint: .isDirectory)
        )

        XCTAssertEqual(directories.directory(for: .appSandbox), directories.appSandbox)
        XCTAssertEqual(directories.directory(for: .downloads), directories.downloads)
        XCTAssertEqual(directories.directory(for: .downloadsSDM), directories.downloadsSDM)
        XCTAssertNil(directories.directory(for: .custom))
    }

    func testDefaultDownloadDestinationResolvesSandboxDownloadsSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let containerData = root.appending(
            path: "ContainerData",
            directoryHint: .isDirectory
        )
        let actualDownloads = root.appending(
            path: "UserDownloads",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: containerData,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: actualDownloads,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sandboxDownloads = containerData.appending(
            path: "Downloads",
            directoryHint: .isDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: sandboxDownloads,
            withDestinationURL: actualDownloads
        )

        let directories = DefaultDownloadDestinationDirectories(
            appSandbox: sandboxDownloads,
            downloads: sandboxDownloads
        )

        XCTAssertEqual(directories.appSandbox, sandboxDownloads.standardizedFileURL)
        XCTAssertEqual(directories.downloads, actualDownloads.standardizedFileURL)
        XCTAssertEqual(
            directories.downloadsSDM,
            actualDownloads.appending(path: "SDM", directoryHint: .isDirectory)
        )
    }
    #endif

    @MainActor
    func testDocumentsAndExternalDefaultDestinationsRemainSelectable() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let external = root.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "SDMAppTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let bookmarks = try DestinationBookmarkStore(
            storeURL: root.appending(path: "destination-bookmarks.plist")
        )
        let directories = DefaultDownloadDestinationDirectories(appSandbox: documents)
        let service = try DownloadService(
            configuration: DownloadManagerConfiguration(
                databaseURL: root.appending(path: "downloads.sqlite3"),
                temporaryDirectory: root.appending(
                    path: "PartialDownloads",
                    directoryHint: .isDirectory
                )
            ),
            destinationDirectory: documents,
            destinationBookmarks: bookmarks,
            defaultDownloadLocation: .appSandbox,
            defaultDestinationDirectories: directories,
            userDefaults: userDefaults
        )

        try service.selectDefaultDestination(.custom, customDirectory: external)
        XCTAssertEqual(service.defaultDownloadLocation, .custom)
        XCTAssertEqual(service.defaultDestinationDirectory, external.standardizedFileURL)

        try service.selectDefaultDestination(.appSandbox)
        XCTAssertEqual(service.defaultDownloadLocation, .appSandbox)
        XCTAssertEqual(service.defaultDestinationDirectory, documents.standardizedFileURL)
        XCTAssertNil(directories.directory(for: .downloads))
        XCTAssertNil(directories.directory(for: .downloadsSDM))

        await service.shutdown()
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
        XCTAssertFalse(DownloadState.finalizing.allows(.cancel))
        XCTAssertFalse(DownloadState.completed.allows(.cancel))
    }

    func testBatchCommandsAreTheIntersectionOfEverySelectedDownload() throws {
        let completed = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/completed.zip")),
            filename: "completed.zip",
            state: .completed
        )
        let failed = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/failed.zip")),
            filename: "failed.zip",
            state: .failed
        )
        let downloading = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/downloading.zip")),
            filename: "downloading.zip",
            state: .downloading
        )
        let snapshots = [completed, failed, downloading]

        XCTAssertEqual(
            snapshots.commonCommands(for: [failed.id, downloading.id]).map(\.title),
            ["Cancel"]
        )
        XCTAssertEqual(
            snapshots.commonCommands(for: [completed.id, failed.id]).map(\.title),
            ["Remove from History"]
        )
        XCTAssertTrue(
            snapshots.commonCommands(for: [completed.id, downloading.id]).isEmpty
        )
        XCTAssertTrue(snapshots.commonCommands(for: []).isEmpty)
        XCTAssertTrue(snapshots.commonCommands(for: [DownloadID()]).isEmpty)
    }

    @MainActor
    func testServiceIgnoresCommandsUnavailableForTheCurrentState() async throws {
        let failed = DownloadSnapshot(
            id: DownloadID(),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/failed.zip")),
            filename: "failed.zip",
            state: .failed
        )
        let service = DownloadService.preview(snapshots: [failed])

        let didPerform = try await service.perform(.pause, on: failed.id)
        let performedIDs = try await service.perform(.pause, on: [failed.id])

        XCTAssertFalse(didPerform)
        XCTAssertTrue(performedIDs.isEmpty)
        XCTAssertFalse(service.commandInFlightIDs.contains(failed.id))
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

    func testDownloadListOrderingUsesLastAttemptInsteadOfLastUpdate() throws {
        let olderAttemptWithNewerUpdate = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            state: .downloading,
            createdAt: 10,
            updatedAt: 100,
            lastAttemptAt: 20
        )
        let newerAttemptWithOlderUpdate = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000002",
            state: .downloading,
            createdAt: 15,
            updatedAt: 30,
            lastAttemptAt: 40
        )

        let result = [olderAttemptWithNewerUpdate, newerAttemptWithOlderUpdate]
            .sortedForDownloadList()

        XCTAssertEqual(
            result.map(\.id),
            [newerAttemptWithOlderUpdate.id, olderAttemptWithNewerUpdate.id]
        )
    }

    func testRecentDownloadsUseStableOrderingForEqualAttemptTimes() throws {
        let olderCreation = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000003",
            state: .queued,
            createdAt: 10,
            updatedAt: 50,
            lastAttemptAt: 30
        )
        let higherID = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000002",
            state: .queued,
            createdAt: 20,
            updatedAt: 40,
            lastAttemptAt: 30
        )
        let lowerID = try makeSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            state: .queued,
            createdAt: 20,
            updatedAt: 60,
            lastAttemptAt: 30
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
            result.map(\.createdAt),
            (2 ... 9).reversed().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    #if os(macOS)
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
    #endif

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
        updatedAt: TimeInterval,
        lastAttemptAt: TimeInterval? = nil
    ) throws -> DownloadSnapshot {
        DownloadSnapshot(
            id: DownloadID(rawValue: try XCTUnwrap(UUID(uuidString: id))),
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/file.bin")),
            filename: "file.bin",
            state: state,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastAttemptAt: lastAttemptAt.map(Date.init(timeIntervalSince1970:)),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
