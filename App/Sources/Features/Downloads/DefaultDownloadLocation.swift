import Foundation

enum DefaultDownloadLocation: String, CaseIterable, Identifiable {
    case appSandbox
    case downloads
    case downloadsSDM
    case custom

    var id: Self { self }

    static var availableLocations: [Self] {
        #if os(macOS)
        allCases
        #else
        [.appSandbox, .custom]
        #endif
    }

    static var fallback: Self {
        #if os(macOS)
        .downloads
        #else
        .appSandbox
        #endif
    }

    var title: String {
        switch self {
        case .appSandbox:
            #if os(macOS)
            "App Sandbox"
            #else
            "SDM Documents"
            #endif
        case .downloads:
            "~/Downloads"
        case .downloadsSDM:
            "~/Downloads/SDM"
        case .custom:
            #if os(macOS)
            "Custom Folder…"
            #else
            "External Folder"
            #endif
        }
    }
}

struct DefaultDownloadDestinationDirectories: Sendable, Equatable {
    let appSandbox: URL
    let downloads: URL?

    init(appSandbox: URL, downloads: URL? = nil) {
        self.appSandbox = appSandbox.standardizedFileURL
        self.downloads = downloads?.resolvingSymlinksInPath().standardizedFileURL
    }

    var downloadsSDM: URL? {
        downloads?.appending(path: "SDM", directoryHint: .isDirectory)
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
