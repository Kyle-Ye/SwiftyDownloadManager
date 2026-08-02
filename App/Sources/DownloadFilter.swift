import SwiftUI

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "All Downloads"
    case downloading = "Downloading"
    case queued = "Queued"
    case completed = "Completed"
    case failed = "Failed"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .downloading:
            "arrow.down.circle"
        case .queued:
            "clock"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}
