import Foundation

struct URLSessionDownloadStore: Sendable {
    let fileURL: URL

    init(databaseURL: URL) {
        let databaseName = databaseURL.deletingPathExtension().lastPathComponent
        fileURL = databaseURL.deletingLastPathComponent().appending(
            path: "\(databaseName)-urlsession.json"
        )
    }

    func load() throws -> [URLSessionDownloadRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try JSONDecoder().decode(
                [URLSessionDownloadRecord].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw DownloadError(
                code: .persistence,
                message: "URLSession history could not be loaded: \(error.localizedDescription)"
            )
        }
    }

    func save(_ records: [URLSessionDownloadRecord]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            throw DownloadError(
                code: .persistence,
                message: "URLSession history could not be saved: \(error.localizedDescription)"
            )
        }
    }
}
