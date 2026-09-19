import Foundation
import XCTest
@testable import SDMCore

final class AuthenticatedDownloadTests: XCTestCase {
    private func context(_ fixture: FixtureServer, path: String = "/auth/", value: String = "valid", expiration: Double? = nil) -> DownloadRequestContext {
        .init(cookies: [.init(name: "sdm_session", value: value, domain: "127.0.0.1", path: path,
                            secure: false, expirationDate: expiration)],
              userAgent: "SDM-Fixture-Browser", referrer: fixture.baseURL)
    }

    private func run(_ path: String, engine: DownloadEngineKind, fixture: FixtureServer,
                     context: DownloadRequestContext?, successful: Bool, connections: Int = 1) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try DownloadManager(configuration: .init(
            databaseURL: root.appending(path: "history.sqlite3"), temporaryDirectory: root.appending(path: "partial"),
            defaultEngine: engine))
        let id = try await manager.enqueue(.init(url: fixture.baseURL.appending(path: path),
            destinationDirectory: root, filename: "Fixture.xip", connectionLimit: connections, requestContext: context))
        let snapshot = try await waitForSnapshot(manager, id: id, timeout: .seconds(15)) {
            $0.state == .completed || $0.state == .failed
        }
        await manager.shutdown()
        if successful {
            XCTAssertEqual(snapshot.state, .completed, "\(engine) \(path): \(snapshot.error?.message ?? "")")
            if let destination = snapshot.destinationURL {
                XCTAssertEqual(try Data(contentsOf: destination), fixturePattern(offset: 0, length: 64 * 1024))
            } else { XCTFail("No destination") }
            if connections > 1 { XCTAssertGreaterThan(snapshot.segments.count, 1) }
        } else {
            XCTAssertEqual(snapshot.state, .failed, "\(engine) \(path)")
            XCTAssertTrue(snapshot.error?.message.contains("web page") == true, snapshot.error?.message ?? "No error")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "Fixture.xip").path))
        }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" || file.lastPathComponent.contains("sqlite3") {
            let data = try Data(contentsOf: file)
            XCTAssertNil(data.range(of: Data("sdm_session".utf8)), "Cookie was persisted in \(file.lastPathComponent)")
            XCTAssertNil(data.range(of: Data("SDM-Fixture-Browser".utf8)), "User-Agent was persisted")
        }
    }

    func testCookieProtectedDownloadsAndRedirectScopeForBothBackends() async throws {
        let fixture = try FixtureServer()
        defer { fixture.stop() }
        for engine in DownloadEngineKind.allCases {
            for path in ["auth/file.xip", "auth/redirect.xip", "auth/rotate.xip", "auth/headers.xip", "auth/cross-path.xip"] {
                try await run(path, engine: engine, fixture: fixture, context: context(fixture), successful: true,
                              connections: engine == .libcurl ? 4 : 1)
            }
            try await run("auth/cross-host.xip", engine: engine, fixture: fixture,
                          context: context(fixture, path: "/"), successful: true)
        }
    }

    func testMissingExpiredAndRejectedCookiesNeverCompleteHTML() async throws {
        let fixture = try FixtureServer()
        defer { fixture.stop() }
        for engine in DownloadEngineKind.allCases {
            try await run("auth/file.xip", engine: engine, fixture: fixture, context: nil, successful: false)
            try await run("auth/file.xip", engine: engine, fixture: fixture,
                          context: context(fixture, expiration: Date.now.timeIntervalSince1970 - 60), successful: false)
            for path in ["auth/expired.xip", "auth/head-expires.xip"] {
                try await run(path, engine: engine, fixture: fixture, context: context(fixture), successful: false)
            }
        }
    }

    func testCurlRetryKeepsCookies() async throws {
        let fixture = try FixtureServer()
        defer { fixture.stop() }
        try await run("auth/flaky.xip", engine: .libcurl, fixture: fixture,
                      context: context(fixture), successful: true, connections: 4)
    }

    func testRequestEncodingOmitsContextAndPreventsAnonymousReenqueue() throws {
        let request = DownloadRequest(url: URL(string: "https://example.com/file.xip")!,
            destinationDirectory: URL(filePath: "/tmp"), requestContext: .init(cookies: [
                .init(name: "private_cookie", value: "SECRET_VALUE", domain: "example.com")
            ]))
        let encoded = try JSONEncoder().encode(request)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("SECRET_VALUE"))
        let restored = try JSONDecoder().decode(DownloadRequest.self, from: encoded)
        XCTAssertTrue(restored.requiresRequestContext)
        XCTAssertTrue(restored.rejectsHTML)
        XCTAssertNil(restored.requestContext)
        XCTAssertThrowsError(try restored.validateContext())
    }
}

extension AuthenticatedDownloadTests {
    func testAuthenticatedPauseResumeAndRecoveryDoNotLoseCredentialsSilently() async throws {
        let fixture = try FixtureServer(fileSize: 512 * 1024, bytesPerSecond: 256 * 1024)
        defer { fixture.stop() }
        for engine in DownloadEngineKind.allCases {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let configuration = DownloadManagerConfiguration(databaseURL: root.appending(path: "history.sqlite3"),
                temporaryDirectory: root.appending(path: "partial"), defaultEngine: engine)
            let manager = try DownloadManager(configuration: configuration)
            let id = try await manager.enqueue(.init(url: fixture.baseURL.appending(path: "auth/file.xip"),
                destinationDirectory: root, connectionLimit: 1, requestContext: context(fixture)))
            _ = try await waitForSnapshot(manager, id: id) { $0.state == .downloading && $0.downloadedBytes > 0 }
            try await manager.pause(id)
            _ = try await waitForSnapshot(manager, id: id) { $0.state == .paused }
            try await manager.resume(id)
            let completed = try await waitForSnapshot(manager, id: id) { $0.state == .completed || $0.state == .failed }
            XCTAssertEqual(completed.state, .completed, completed.error?.message ?? "")
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(completed.destinationURL)), fixturePattern(offset: 0, length: 512 * 1024))
            // A second, paused authenticated task must not resume anonymously after restart.
            let pending = try await manager.enqueue(.init(url: fixture.baseURL.appending(path: "auth/file.xip"),
                destinationDirectory: root, connectionLimit: 1, requestContext: context(fixture)))
            _ = try await waitForSnapshot(manager, id: pending) { $0.state == .downloading && $0.downloadedBytes > 0 }
            try await manager.pause(pending)
            _ = try await waitForSnapshot(manager, id: pending) { $0.state == .paused }
            await manager.shutdown()
            let restored = try DownloadManager(configuration: configuration)
            _ = try await waitForSnapshot(restored, id: pending) { $0.state == .paused }
            do {
                try await restored.resume(pending)
                let failed = try await waitForSnapshot(restored, id: pending) { $0.state == .failed }
                XCTAssertTrue(failed.error?.message.contains("browser session") == true)
            } catch let error as DownloadError {
                XCTAssertTrue(error.message.contains("browser session"), error.message)
            }
            await restored.shutdown()
        }
    }

    func testCookieValidationRejectsHeaderInjectionAndPreservesSecureHostAndPathScope() throws {
        let url = URL(string: "https://download.example.com/private/file.xip")!
        let cookie = DownloadCookie(name: "session", value: "private", domain: "download.example.com", path: "/private", secure: true)
        XCTAssertTrue(cookie.matches(url))
        XCTAssertFalse(cookie.matches(URL(string: "http://download.example.com/private/file.xip")!))
        XCTAssertFalse(cookie.matches(URL(string: "https://sub.download.example.com/private/file.xip")!))
        XCTAssertFalse(cookie.matches(URL(string: "https://download.example.com/privately/file.xip")!))
        let injected = DownloadRequestContext(cookies: [
            .init(name: "session", value: "private\r\nX-Injected: value", domain: "download.example.com")
        ])
        XCTAssertThrowsError(try injected.validate(for: url))
    }
}
