import Foundation

@MainActor
final class DestinationBookmarkStore {
    private struct Record: Codable {
        let path: String
        let bookmark: Data
        let owners: [String]?
    }

    private struct Entry {
        var bookmark: Data
        var owners: Set<String>
        var isLegacy: Bool

        func mergingOwners(from existing: Self?) -> Self {
            var merged = self
            merged.owners.formUnion(existing?.owners ?? [])
            return merged
        }
    }

    private let storeURL: URL
    private var entriesByPath: [String: Entry]
    private var activeURLsByPath: [String: URL] = [:]

    init(storeURL: URL) throws {
        self.storeURL = storeURL
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let data = try Data(contentsOf: storeURL)
            let records = try PropertyListDecoder().decode([Record].self, from: data)
            entriesByPath = Dictionary(
                uniqueKeysWithValues: records.map { record in
                    (
                        record.path,
                        Entry(
                            bookmark: record.bookmark,
                            owners: Set(record.owners ?? []),
                            isLegacy: record.owners == nil
                        )
                    )
                }
            )
        } else {
            entriesByPath = [:]
        }
        restoreAccess()
    }

    @discardableResult
    func authorize(_ directory: URL, owner: String) throws -> URL {
        let requestedURL = directory.standardizedFileURL
        let requestedPath = requestedURL.path(percentEncoded: false)
        let path = if entriesByPath[requestedPath] != nil {
            requestedPath
        } else if let activePath = activeURLsByPath.first(where: { _, activeURL in
            activeURL.standardizedFileURL == requestedURL
        })?.key {
            activePath
        } else {
            requestedPath
        }
        let previousEntries = entriesByPath
        let wasAlreadyActive = activeURLsByPath[path] != nil
        let authorizedURL: URL
        let bookmark: Data
        let didStartAccess: Bool

        if let activeURL = activeURLsByPath[path],
           let entry = entriesByPath[path] {
            authorizedURL = activeURL
            bookmark = entry.bookmark
            didStartAccess = false
        } else if let entry = entriesByPath[path] {
            var isStale = false
            authorizedURL = try URL(
                resolvingBookmarkData: entry.bookmark,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
            didStartAccess = authorizedURL.startAccessingSecurityScopedResource()
            if isStale {
                do {
                    bookmark = try authorizedURL.bookmarkData(
                        options: Self.bookmarkCreationOptions,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } catch {
                    if didStartAccess {
                        authorizedURL.stopAccessingSecurityScopedResource()
                    }
                    throw error
                }
            } else {
                bookmark = entry.bookmark
            }
        } else {
            authorizedURL = requestedURL
            didStartAccess = authorizedURL.startAccessingSecurityScopedResource()
            do {
                bookmark = try authorizedURL.bookmarkData(
                    options: Self.bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                if didStartAccess {
                    authorizedURL.stopAccessingSecurityScopedResource()
                }
                throw error
            }
        }

        removeOwner(owner)
        entriesByPath[path] = Entry(
            bookmark: bookmark,
            owners: [owner],
            isLegacy: false
        ).mergingOwners(from: entriesByPath[path])
        if didStartAccess {
            activeURLsByPath[path] = authorizedURL
        }

        do {
            try persist()
            stopUnownedAccess()
            return authorizedURL
        } catch {
            entriesByPath = previousEntries
            if didStartAccess, !wasAlreadyActive {
                authorizedURL.stopAccessingSecurityScopedResource()
                activeURLsByPath[path] = nil
            }
            throw error
        }
    }

    func release(owner: String) throws {
        let previousEntries = entriesByPath
        removeOwner(owner)
        do {
            try persist()
            stopUnownedAccess()
        } catch {
            entriesByPath = previousEntries
            throw error
        }
    }

    func stopAllAccess() {
        for url in activeURLsByPath.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLsByPath.removeAll()
    }

    private func removeOwner(_ owner: String) {
        for path in entriesByPath.keys {
            entriesByPath[path]?.owners.remove(owner)
        }
    }

    private func stopUnownedAccess() {
        let inactivePaths = activeURLsByPath.keys.filter { path in
            guard let entry = entriesByPath[path] else { return true }
            return entry.owners.isEmpty && !entry.isLegacy
        }
        for path in inactivePaths {
            activeURLsByPath[path]?.stopAccessingSecurityScopedResource()
            activeURLsByPath[path] = nil
        }
    }

    private func restoreAccess() {
        var didRefreshBookmark = false
        for (storedPath, entry) in entriesByPath
            where entry.isLegacy || !entry.owners.isEmpty {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: entry.bookmark,
                    options: Self.bookmarkResolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                if url.startAccessingSecurityScopedResource() {
                    activeURLsByPath[storedPath] = url
                }
                if isStale {
                    entriesByPath[storedPath]?.bookmark = try url.bookmarkData(
                        options: Self.bookmarkCreationOptions,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    didRefreshBookmark = true
                }
            } catch {
                // A provider can be temporarily offline. Keep its bookmark so the
                // user can reconnect or replace it without disabling the store.
            }
        }
        if didRefreshBookmark {
            try? persist()
        }
    }

    private func persist() throws {
        let records = entriesByPath
            .map { path, entry in
                Record(
                    path: path,
                    bookmark: entry.bookmark,
                    owners: entry.isLegacy ? nil : entry.owners.sorted()
                )
            }
            .sorted { $0.path < $1.path }
        let data = try PropertyListEncoder().encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope, .withoutUI]
        #else
        [.withoutUI]
        #endif
    }
}
