import Foundation
import SDMEngineTestSupport
import XCTest
@testable import SDMCore

final class PersistenceMigrationTests: XCTestCase {
    func testMalformedDatabaseIsNotReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "downloads.sqlite3")
        let originalData = Data("not a sqlite database".utf8)
        try originalData.write(to: databaseURL)

        XCTAssertThrowsError(try DownloadManager(configuration: DownloadManagerConfiguration(
            databaseURL: databaseURL,
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))) { error in
            XCTAssertEqual((error as? DownloadError)?.code, .persistence)
        }
        XCTAssertEqual(try Data(contentsOf: databaseURL), originalData)
    }

    func testInvalidPersistedStateIsIsolatedAsFailedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "downloads.sqlite3")
        let id = DownloadID()
        let created = databaseURL.path.withCString { databasePath in
            id.description.withCString { idText in
                root.path.withCString { destinationPath in
                    sdm_test_create_v1_database(
                        databasePath,
                        idText,
                        destinationPath,
                        1_754_000_000_000
                    )
                }
            }
        }
        XCTAssertTrue(created)
        XCTAssertTrue(databaseURL.path.withCString { databasePath in
            id.description.withCString { idText in
                sdm_test_set_download_state(databasePath, idText, 999)
            }
        })

        let manager = try DownloadManager(configuration: DownloadManagerConfiguration(
            databaseURL: databaseURL,
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))
        let restored = try await waitForSnapshot(manager, id: id) {
            $0.state == .failed
        }
        XCTAssertEqual(restored.error?.code, .persistence)
        XCTAssertEqual(restored.error?.message, "Persisted download state was invalid")
        await manager.shutdown()
    }

    func testNewerSchemaReturnsTypedPersistenceError() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "downloads.sqlite3")
        XCTAssertTrue(databaseURL.path.withCString {
            sdm_test_set_database_user_version($0, 99)
        })

        XCTAssertThrowsError(try DownloadManager(configuration: DownloadManagerConfiguration(
            databaseURL: databaseURL,
            temporaryDirectory: root.appending(path: "partial", directoryHint: .isDirectory)
        ))) { error in
            XCTAssertEqual((error as? DownloadError)?.code, .persistence)
        }
    }

    func testVersionOneHistoryMigratesInPlaceToVersionTwo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "downloads.sqlite3")
        let id = DownloadID()
        let updatedMilliseconds: UInt64 = 1_754_000_000_000
        let created = databaseURL.path.withCString { databasePath in
            id.description.withCString { idText in
                root.path.withCString { destinationPath in
                    sdm_test_create_v1_database(
                        databasePath,
                        idText,
                        destinationPath,
                        updatedMilliseconds
                    )
                }
            }
        }
        XCTAssertTrue(created)

        let manager = try DownloadManager(configuration: DownloadManagerConfiguration(
            databaseURL: databaseURL,
            temporaryDirectory: root.appending(
                path: "PartialDownloads",
                directoryHint: .isDirectory
            )
        ))
        let restored = try await waitForSnapshot(manager, id: id) {
            $0.state == .cancelled
        }
        let expectedDate = Date(
            timeIntervalSince1970: Double(updatedMilliseconds) / 1_000
        )
        XCTAssertEqual(restored.createdAt, expectedDate)
        XCTAssertEqual(restored.lastAttemptAt, expectedDate)
        XCTAssertNil(restored.startedAt)
        XCTAssertNil(restored.completedAt)
        XCTAssertEqual(restored.updatedAt, expectedDate)
        let events = try await manager.diagnosticEvents(for: id)
        XCTAssertTrue(events.contains {
            $0.message == "Loaded persisted download history."
        })
        await manager.shutdown()

        let version = databaseURL.path.withCString(sdm_test_database_user_version)
        XCTAssertEqual(version, 2)
    }
}
