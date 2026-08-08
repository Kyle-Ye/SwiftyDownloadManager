import Foundation
import SDMCore

struct AppStoragePaths: Sendable, Equatable {
    static let directoryName = "SwiftyDownloadManager"

    let rootDirectory: URL
    let databaseURL: URL
    let partialDownloadsDirectory: URL
    let destinationBookmarksURL: URL

    static func live(fileManager: FileManager = .default) throws -> AppStoragePaths {
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try resolving(
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager
        )
    }

    static func resolving(
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> AppStoragePaths {
        guard applicationSupportDirectory.isFileURL else {
            throw StorageError.invalidApplicationSupportDirectory
        }
        let rootDirectory = applicationSupportDirectory.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        let partialDownloadsDirectory = rootDirectory.appending(
            path: "PartialDownloads",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: partialDownloadsDirectory,
            withIntermediateDirectories: true
        )
        return AppStoragePaths(
            rootDirectory: rootDirectory,
            databaseURL: rootDirectory.appending(path: "downloads.sqlite3"),
            partialDownloadsDirectory: partialDownloadsDirectory,
            destinationBookmarksURL: rootDirectory.appending(
                path: "destination-bookmarks.plist"
            )
        )
    }

    func managerConfiguration(
        defaultEngine: DownloadEngineKind = .libcurl,
        urlSessionIdentifier: String? = nil
    ) -> DownloadManagerConfiguration {
        DownloadManagerConfiguration(
            databaseURL: databaseURL,
            temporaryDirectory: partialDownloadsDirectory,
            defaultEngine: defaultEngine,
            urlSessionIdentifier: urlSessionIdentifier
        )
    }

    private enum StorageError: LocalizedError {
        case invalidApplicationSupportDirectory

        var errorDescription: String? {
            "Application Support must be a local file URL."
        }
    }
}
