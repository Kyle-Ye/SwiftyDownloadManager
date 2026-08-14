import Foundation

enum DefaultDownloadLocation: String, CaseIterable, Identifiable {
    case appSandbox
    case downloads
    case downloadsSDM
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .appSandbox:
            "App Sandbox"
        case .downloads:
            "~/Downloads"
        case .downloadsSDM:
            "~/Downloads/SDM"
        case .custom:
            "Custom Folder…"
        }
    }
}

struct DefaultDownloadDestinationDirectories: Sendable, Equatable {
    let appSandbox: URL
    let downloads: URL

    init(appSandbox: URL, downloads: URL) {
        self.appSandbox = appSandbox.standardizedFileURL
        self.downloads = downloads.resolvingSymlinksInPath().standardizedFileURL
    }

    var downloadsSDM: URL {
        downloads.appending(path: "SDM", directoryHint: .isDirectory)
    }

    func directory(for location: DefaultDownloadLocation) -> URL? {
        switch location {
        case .appSandbox:
            appSandbox
        case .downloads:
            downloads
        case .downloadsSDM:
            downloadsSDM
        case .custom:
            nil
        }
    }
}
