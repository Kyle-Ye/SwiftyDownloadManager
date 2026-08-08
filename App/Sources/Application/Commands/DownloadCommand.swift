import SwiftUI

enum DownloadCommand: CaseIterable, Identifiable {
    case pause
    case resume
    case cancel
    case retry
    case remove

    var id: Self { self }

    var title: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case .cancel: "Cancel"
        case .retry: "Retry"
        case .remove: "Remove from History"
        }
    }

    var systemImage: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .cancel: "xmark"
        case .retry: "arrow.clockwise"
        case .remove: "trash"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .cancel, .remove: .destructive
        default: nil
        }
    }

    func title(forSelectionCount count: Int) -> String {
        guard count > 1 else { return title }
        return switch self {
        case .pause: "Pause \(count) Downloads"
        case .resume: "Resume \(count) Downloads"
        case .cancel: "Cancel \(count) Downloads"
        case .retry: "Retry \(count) Downloads"
        case .remove: "Remove \(count) from History"
        }
    }
}
