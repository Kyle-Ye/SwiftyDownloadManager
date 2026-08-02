import Foundation
@testable import SDMCore

final class FixtureServer: @unchecked Sendable {
    let fileURL: URL

    private let process: Process

    init(
        fileSize: Int = 64 * 1024,
        bytesPerSecond: Int = 0,
        maximumConnections: Int = 8
    ) throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let serverURL = repositoryURL.appending(path: "Fixture/range_server.py")
        let output = Pipe()
        let error = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            serverURL.path,
            "--port", "0",
            "--file-size", String(fileSize),
            "--bytes-per-second", String(bytesPerSecond),
            "--max-connections", String(maximumConnections),
            "--quiet",
        ]
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let readiness = output.fileHandleForReading.availableData
        guard !readiness.isEmpty,
              let message = String(data: readiness, encoding: .utf8),
              let portRange = message.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression),
              let port = Int(message[portRange].split(separator: ":")[1]) else {
            process.terminate()
            process.waitUntilExit()
            let diagnostic = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw FixtureServerError.failedToStart(diagnostic)
        }

        self.process = process
        fileURL = URL(string: "http://127.0.0.1:\(port)/empty.bin")!
    }

    deinit {
        stop()
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

enum FixtureServerError: Error {
    case failedToStart(String)
}

func fixturePattern(offset: Int, length: Int) -> Data {
    Data((0..<length).map { UInt8((((offset + $0) * 31 + 17) % 251) + 1) })
}

func waitForSnapshot(
    _ manager: DownloadManager,
    id: DownloadID,
    timeout: Duration = .seconds(5),
    matching predicate: @escaping @Sendable (DownloadSnapshot) -> Bool
) async throws -> DownloadSnapshot {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        do {
            let snapshot = try await manager.snapshot(for: id)
            if predicate(snapshot) {
                return snapshot
            }
        } catch let error as DownloadError where error.code == .notFound {
            // Engine restoration happens on its serialized worker before the
            // first polling tick, so a newly created manager can briefly be empty.
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw FixtureServerError.failedToStart("Timed out waiting for download state")
}
