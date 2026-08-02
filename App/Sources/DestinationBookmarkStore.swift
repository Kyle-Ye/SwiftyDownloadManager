import Foundation

@MainActor
final class DestinationBookmarkStore {
    private struct Record: Codable {
        let path: String
        let bookmark: Data
    }

    private let storeURL: URL
    private var bookmarksByPath: [String: Data]
    private var activeURLsByPath: [String: URL] = [:]

    init(storeURL: URL) throws {
        self.storeURL = storeURL
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let data = try Data(contentsOf: storeURL)
            let records = try PropertyListDecoder().decode([Record].self, from: data)
            bookmarksByPath = Dictionary(
                uniqueKeysWithValues: records.map { ($0.path, $0.bookmark) }
            )
        } else {
            bookmarksByPath = [:]
        }
        try restoreAccess()
    }

    @discardableResult
    func authorize(_ directory: URL) throws -> URL {
        let standardizedURL = directory.standardizedFileURL
        let path = standardizedURL.path(percentEncoded: false)
        if let activeURL = activeURLsByPath[path] {
            return activeURL
        }

        let didStartAccess = standardizedURL.startAccessingSecurityScopedResource()
        let previousBookmark = bookmarksByPath[path]
        do {
            let bookmark = try standardizedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarksByPath[path] = bookmark
            if didStartAccess {
                activeURLsByPath[path] = standardizedURL
            }
            try persist()
            return standardizedURL
        } catch {
            bookmarksByPath[path] = previousBookmark
            activeURLsByPath[path] = nil
            if didStartAccess {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    func stopAllAccess() {
        for url in activeURLsByPath.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLsByPath.removeAll()
    }

    private func restoreAccess() throws {
        var refreshedBookmarks = bookmarksByPath
        for (storedPath, bookmark) in bookmarksByPath {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let standardizedURL = url.standardizedFileURL
            if standardizedURL.startAccessingSecurityScopedResource() {
                activeURLsByPath[storedPath] = standardizedURL
            }
            if isStale {
                refreshedBookmarks[storedPath] = try standardizedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        }
        if refreshedBookmarks != bookmarksByPath {
            bookmarksByPath = refreshedBookmarks
            try persist()
        }
    }

    private func persist() throws {
        let records = bookmarksByPath
            .map { Record(path: $0.key, bookmark: $0.value) }
            .sorted { $0.path < $1.path }
        let data = try PropertyListEncoder().encode(records)
        try data.write(to: storeURL, options: .atomic)
    }
}
