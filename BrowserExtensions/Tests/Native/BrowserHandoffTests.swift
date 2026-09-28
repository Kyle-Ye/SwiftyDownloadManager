import Foundation
import XCTest
@testable import SDMBrowserHandoff

final class BrowserHandoffTests: XCTestCase {
    private let payload = Data("{\"requestContext\":{\"cookies\":[{\"name\":\"session\",\"value\":\"private-value\"}]}}".utf8)

    func testSafariStagingIsEncryptedAndConsumedOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SafariHandoffStore(directory: directory)
        let ticket = try store.stage(payload)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let stored = try Data(contentsOf: file)
        XCTAssertNil(stored.range(of: Data("private-value".utf8)))
        XCTAssertFalse(ticket.callbackURL.absoluteString.contains("private-value"))
        let received = try XCTUnwrap(BrowserHandoffTicket(callbackURL: ticket.callbackURL))
        XCTAssertEqual(try store.consume(received), payload)
        XCTAssertThrowsError(try store.consume(received))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTamperingAndExpiredSafariHandoffsAreRejected() throws {
        let ticket = BrowserHandoffTicket(browser: "chrome")
        var sealed = try ticket.seal(payload)
        sealed[sealed.count - 1] ^= 1
        XCTAssertThrowsError(try ticket.open(sealed))
        XCTAssertThrowsError(try BrowserHandoffTicket(browser: "chrome").open(ticket.seal(payload)))
        XCTAssertThrowsError(try ticket.seal(Data(repeating: 0, count: BrowserHandoffTicket.maximumPayloadSize + 1)))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SafariHandoffStore(directory: directory)
        let expired = try store.stage(payload)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-120)], ofItemAtPath: file.path)
        XCTAssertThrowsError(try store.consume(expired))
    }

    func testTicketsRejectMalformedOrAmbiguousCallbackParameters() {
        let ticket = BrowserHandoffTicket(browser: "safari")
        XCTAssertNil(BrowserHandoffTicket(callbackURL: URL(string: ticket.callbackURL.absoluteString + "&browser=chrome")!))
        XCTAssertNil(BrowserHandoffTicket(callbackURL: URL(string: "swifty-download-manager://handoff?id=bad&browser=safari&key=AA==")!))
    }

    #if os(macOS)
    func testChromeLoopbackHandoffAndIdempotentEncryptedReceipt() async throws {
        let server = ChromeHandoffServer(port: 0)
        let ticket = BrowserHandoffTicket(browser: "chrome")
        let receiving = Task { try await server.receive(ticket) }
        var port: UInt16?
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            port = await server.listeningPort
            if let port, port != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let boundPort = try XCTUnwrap(port)
        let url = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(boundPort)"))
        var request = URLRequest(url: url)
        request.setValue("chrome-extension://abcdefghijklmnopabcdefghijklmnop", forHTTPHeaderField: "Origin")
        request.setValue("sdm.handoff.v1", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let envelope = try JSONSerialization.data(withJSONObject: [
            "id": ticket.id.uuidString.lowercased(), "sealed": try ticket.seal(payload).base64EncodedString(),
        ])
        let socket = session.webSocketTask(with: request)
        socket.resume()
        try await socket.send(.data(envelope))
        let received = try await receiving.value
        XCTAssertEqual(received, payload)
        await server.complete(ticket, accepted: true)
        let response = try await socket.receive()
        guard case .string(let receipt) = response else { return XCTFail("Expected encrypted receipt") }
        XCTAssertEqual(try ticket.open(XCTUnwrap(Data(base64Encoded: receipt))), Data("{\"accepted\":true}".utf8))
        // Retrying the same ciphertext gets a receipt without importing another task.
        let retry = session.webSocketTask(with: request)
        retry.resume()
        try await retry.send(.data(envelope))
        guard case .string(let repeated) = try await retry.receive() else { return XCTFail("Missing retry receipt") }
        XCTAssertEqual(try ticket.open(XCTUnwrap(Data(base64Encoded: repeated))), Data("{\"accepted\":true}".utf8))
    }
    #endif
}
