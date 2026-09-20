#if os(macOS)
import CryptoKit
import Foundation
import Network

actor ChromeHandoffServer {
    static let shared = ChromeHandoffServer()
    private let port: UInt16

    init(port: UInt16 = 10027) { self.port = port }

    var listeningPort: UInt16? { listener?.port?.rawValue }
    private let queue = DispatchQueue(label: "top.kyleye.sdm.browser-handoff")
    private var listener: NWListener?
    private var pending: [UUID: Pending] = [:]

    private struct Envelope: Decodable { let id: UUID; let sealed: Data }
    private struct Pending {
        let ticket: BrowserHandoffTicket
        var continuation: CheckedContinuation<Data, any Error>?
        var digest: Data?
        var receipt: Data?
        var connections: [NWConnection] = []
    }

    func receive(_ ticket: BrowserHandoffTicket) async throws -> Data {
        guard pending[ticket.id] == nil, pending.count < 128 else { throw BrowserHandoffError.invalidPayload }
        try start()
        return try await withCheckedThrowingContinuation { continuation in
            pending[ticket.id] = Pending(ticket: ticket, continuation: continuation)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(BrowserHandoffTicket.lifetime))
                await self?.expire(ticket.id)
            }
        }
    }

    func complete(_ ticket: BrowserHandoffTicket, accepted: Bool) {
        guard var value = pending[ticket.id] else { return }
        let data = Data((accepted ? "{\"accepted\":true}" : "{\"accepted\":false}").utf8)
        value.receipt = try? ticket.seal(data)
        let connections = value.connections
        value.connections = []
        pending[ticket.id] = value
        for connection in connections { send(value.receipt, to: connection) }
    }

    private func start() throws {
        guard listener == nil else { return }
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.maximumMessageSize = 160 * 1024
        websocket.setClientRequestHandler(queue) { protocols, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let permitted = URL(string: origin)?.scheme == "chrome-extension" && protocols.contains("sdm.handoff.v1")
            return NWProtocolWebSocket.Response(status: permitted ? .accept : .reject,
                subprotocol: permitted ? "sdm.handoff.v1" : nil)
        }
        let parameters = NWParameters.tcp
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw BrowserHandoffError.unavailable }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { await self?.failed() } }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, error in
            guard error == nil, let data else { connection.cancel(); return }
            Task { await self?.received(data, from: connection) }
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            connection.cancel()
        }
    }

    private func received(_ data: Data, from connection: NWConnection) {
        do {
            guard data.count <= 160 * 1024 else { throw BrowserHandoffError.invalidPayload }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard var value = pending[envelope.id] else { throw BrowserHandoffError.expired }
            let plaintext = try value.ticket.open(envelope.sealed)
            let digest = Data(SHA256.hash(data: plaintext))
            if let previous = value.digest {
                guard previous == digest else { throw BrowserHandoffError.invalidPayload }
                if let receipt = value.receipt { send(receipt, to: connection); return }
            } else {
                value.digest = digest
            }
            guard value.connections.count < 16 else { throw BrowserHandoffError.unavailable }
            value.connections.append(connection)
            let continuation = value.continuation
            value.continuation = nil
            pending[envelope.id] = value
            continuation?.resume(returning: plaintext)
        } catch { connection.cancel() }
    }

    private func send(_ receipt: Data?, to connection: NWConnection) {
        guard let receipt else { connection.cancel(); return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "receipt", metadata: [metadata])
        connection.send(content: Data(receipt.base64EncodedString().utf8), contentContext: context,
            isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func expire(_ id: UUID) {
        guard let value = pending.removeValue(forKey: id) else { return }
        value.continuation?.resume(throwing: BrowserHandoffError.expired)
        for connection in value.connections { connection.cancel() }
        if pending.isEmpty { listener?.cancel(); listener = nil }
    }

    private func failed() {
        listener?.cancel()
        listener = nil
        for id in Array(pending.keys) { expire(id) }
    }
}
#endif
