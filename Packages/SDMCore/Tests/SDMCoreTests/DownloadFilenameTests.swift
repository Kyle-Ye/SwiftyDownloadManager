import Foundation
import XCTest
@testable import SDMCore

final class DownloadFilenameTests: XCTestCase {
    func testRedirectFilenameIsAvailableDuringDownloadAndPreservesOverrides() async throws {
        let size = 256 * 1024
        let fixture = try FixtureServer(fileSize: size, bytesPerSecond: 256 * 1024)
        defer { fixture.stop() }
        let scenarios: [(query: String, override: String?, expected: String)] = [
            ("path=/Developer_Tools/Xcode_27.1_beta/Xcode_27.1_beta.xip", nil, "Xcode_27.1_beta.xip"),
            ("encoded=1", nil, "Xcode 27.1 beta.xip"),
            ("disposition=1", nil, "Xcode-from-header.xip"),
            ("disposition=1", "My Xcode.xip", "My Xcode.xip"),
        ]
        for engine in DownloadEngineKind.allCases {
            for scenario in scenarios {
                let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: root) }
                let manager = try DownloadManager(configuration: .init(
                    databaseURL: root.appending(path: "history.sqlite3"),
                    temporaryDirectory: root.appending(path: "partial"), defaultEngine: engine))
                let url = try XCTUnwrap(URL(string: "auth/download?\(scenario.query)", relativeTo: fixture.baseURL)?.absoluteURL)
                let context = DownloadRequestContext(cookies: [
                    .init(name: "sdm_session", value: "valid", domain: "127.0.0.1", path: "/auth/", secure: false),
                ])
                let id = try await manager.enqueue(.init(url: url, destinationDirectory: root,
                    filename: scenario.override, connectionLimit: 1, requestContext: context))
                let active = try await waitForSnapshot(manager, id: id) {
                    $0.state == .downloading && $0.downloadedBytes > 0
                }
                XCTAssertEqual(active.filename, scenario.expected, "\(engine): name before completion")
                XCTAssertEqual(active.finalURL?.lastPathComponent,
                    scenario.query == "encoded=1" ? "Xcode 27.1 beta.xip" : "Xcode_27.1_beta.xip")
                if scenario.query.hasPrefix("path=") {
                    try await manager.pause(id)
                    let paused = try await waitForSnapshot(manager, id: id) { $0.state == .paused }
                    XCTAssertEqual(paused.filename, scenario.expected)
                    try await manager.resume(id)
                }
                let completed = try await waitForSnapshot(manager, id: id) {
                    $0.state == .completed || $0.state == .failed
                }
                XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
                XCTAssertEqual(completed.filename, scenario.expected)
                let savedURL = try XCTUnwrap(completed.destinationURL)
                XCTAssertEqual(savedURL.lastPathComponent, scenario.expected)
                XCTAssertEqual(try Data(contentsOf: savedURL), fixturePattern(offset: 0, length: size))
                await manager.shutdown()
            }
        }
    }
}
