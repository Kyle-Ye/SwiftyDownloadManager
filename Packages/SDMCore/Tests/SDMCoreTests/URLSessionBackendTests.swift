import Foundation
import XCTest
@testable import SDMCore

final class URLSessionBackendTests: XCTestCase {
    func testURLSessionDelegateTaskTrackerWaitsForTerminalOperations() async {
        let tracker = URLSessionDelegateTaskTracker()
        let recorder = URLSessionDelegateEventRecorder()

        tracker.start {
            try? await Task.sleep(for: .milliseconds(50))
            await recorder.append(1)
        }
        tracker.start {
            await recorder.append(2)
        }
        await tracker.waitForTrackedTasks()

        let values = await recorder.values
        XCTAssertEqual(Set(values), [1, 2])
    }

    func testCoordinatedFinalizerRefusesToOverwriteWithoutReplacePolicy() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.bin")
        let destination = root.appending(path: "destination.bin")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        XCTAssertThrowsError(
            try CoordinatedFileFinalizer.move(
                from: source,
                to: destination,
                replacesExisting: false
            )
        )
        XCTAssertEqual(try Data(contentsOf: source), Data("new".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
    }

    func testCoordinatedFinalizerReplacesCommittedDestination() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.bin")
        let destination = root.appending(path: "destination.bin")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        try CoordinatedFileFinalizer.move(
            from: source,
            to: destination,
            replacesExisting: true
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
    }

    func testURLSessionDownloadIsByteCorrect() async throws {
        let fixture = try FixtureServer(fileSize: 48 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory),
            defaultEngine: .urlSession
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
        XCTAssertEqual(completed.engine, .urlSession)
        XCTAssertEqual(completed.contentLength, 48 * 1024)
        let destinationURL = try XCTUnwrap(completed.destinationURL)
        XCTAssertEqual(
            try Data(contentsOf: destinationURL),
            fixturePattern(offset: 0, length: 48 * 1024)
        )
        await manager.shutdown()
    }

    func testFreshBackgroundSessionStartsQueuedDownload() async throws {
        let fixture = try FixtureServer(fileSize: 20 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory),
            defaultEngine: .urlSession,
            urlSessionIdentifier: "top.kyleye.sdm.tests.\(UUID().uuidString)"
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
        XCTAssertEqual(completed.engine, .urlSession)
        await manager.shutdown()
    }

    func testURLSessionRejectsMultiConnectionRequestsWithTypedError() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root,
            defaultEngine: .urlSession
        ))

        do {
            _ = try await manager.enqueue(DownloadRequest(
                url: try XCTUnwrap(URL(string: "https://example.com/file.zip")),
                destinationDirectory: root,
                connectionLimit: 2
            ))
            XCTFail("Expected an unsupported feature error")
        } catch let error as DownloadError {
            XCTAssertEqual(error.code, .unsupportedFeature)
        }
        await manager.shutdown()
    }

    func testEngineDescriptorsExposeDifferentCapabilities() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root,
            urlSessionIdentifier: "top.kyleye.sdm.tests.background"
        ))
        let descriptors = await manager.engineDescriptors()
        let curl = try XCTUnwrap(descriptors.first { $0.kind == .libcurl })
        let urlSession = try XCTUnwrap(descriptors.first { $0.kind == .urlSession })

        XCTAssertTrue(curl.supports(.multiConnectionTransfers))
        XCTAssertTrue(curl.supports(.bandwidthLimiting))
        XCTAssertFalse(curl.supports(.backgroundTransfers))
        XCTAssertTrue(urlSession.supports(.backgroundTransfers))
        #if os(macOS)
        XCTAssertTrue(curl.supports(.systemTrustStore))
        XCTAssertFalse(curl.supports(.bundledCertificateAuthorities))
        #else
        XCTAssertFalse(curl.supports(.systemTrustStore))
        XCTAssertTrue(curl.supports(.bundledCertificateAuthorities))
        #endif
        XCTAssertFalse(urlSession.supports(.multiConnectionTransfers))
        XCTAssertEqual(urlSession.maximumConnectionsPerDownload, 1)
        await manager.shutdown()
    }

    func testHTTPFailureReleasesSchedulerSlot() async throws {
        let fixture = try FixtureServer(fileSize: 16 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory),
            maximumActiveDownloads: 1,
            defaultEngine: .urlSession
        ))
        let failedID = try await manager.enqueue(DownloadRequest(
            url: fixture.baseURL.appending(path: "missing.bin"),
            destinationDirectory: root,
            connectionLimit: 1
        ))
        let completedID = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 1
        ))

        let failed: DownloadSnapshot
        do {
            failed = try await waitForSnapshot(manager, id: failedID) { $0.state == .failed }
        } catch {
            let snapshots = try await manager.allSnapshots()
            XCTFail("HTTP failure did not settle: \(snapshots.map { ($0.id, $0.state) })")
            throw error
        }
        let completed: DownloadSnapshot
        do {
            completed = try await waitForSnapshot(manager, id: completedID) {
                $0.state == .completed || $0.state == .failed
            }
        } catch {
            let snapshots = try await manager.allSnapshots()
            XCTFail("Following download did not settle: \(snapshots.map { ($0.id, $0.state) })")
            throw error
        }

        XCTAssertEqual(failed.error?.code, .protocolViolation)
        XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
        await manager.shutdown()
    }

    func testChangingDefaultEngineOnlyAffectsNewDownloads() async throws {
        let fixture = try FixtureServer(fileSize: 24 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory),
            defaultEngine: .libcurl
        ))
        let curlID = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 1
        ))
        let curlSnapshot = try await waitForSnapshot(manager, id: curlID) {
            $0.state == .completed || $0.state == .failed
        }

        try await manager.setDefaultEngine(.urlSession)
        let urlSessionID = try await manager.enqueue(DownloadRequest(
            url: fixture.fileURL,
            destinationDirectory: root,
            connectionLimit: 1
        ))
        let urlSessionSnapshot = try await waitForSnapshot(manager, id: urlSessionID) {
            $0.state == .completed || $0.state == .failed
        }

        XCTAssertEqual(curlSnapshot.state, .completed, curlSnapshot.error?.message ?? "")
        XCTAssertEqual(curlSnapshot.engine, .libcurl)
        XCTAssertEqual(urlSessionSnapshot.state, .completed, urlSessionSnapshot.error?.message ?? "")
        XCTAssertEqual(urlSessionSnapshot.engine, .urlSession)
        let selectedEngine = await manager.selectedEngine()
        let engines = Set(try await manager.allSnapshots().map(\.engine))
        XCTAssertEqual(selectedEngine, .urlSession)
        XCTAssertEqual(engines, [.libcurl, .urlSession])
        await manager.shutdown()
    }

    func testDownloadIdentityIsUniqueAcrossEngines() async throws {
        let fixture = try FixtureServer(fileSize: 8 * 1024)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "downloads.sqlite3"),
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
        let id = DownloadID()
        _ = try await manager.enqueue(
            DownloadRequest(
                id: id,
                url: fixture.fileURL,
                destinationDirectory: root,
                connectionLimit: 1
            ),
            using: .libcurl
        )

        do {
            _ = try await manager.enqueue(
                DownloadRequest(
                    id: id,
                    url: fixture.fileURL,
                    destinationDirectory: root,
                    connectionLimit: 1
                ),
                using: .urlSession
            )
            XCTFail("Expected a duplicate identity error")
        } catch let error as DownloadError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
        await manager.shutdown()
    }
}

private actor URLSessionDelegateEventRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}
