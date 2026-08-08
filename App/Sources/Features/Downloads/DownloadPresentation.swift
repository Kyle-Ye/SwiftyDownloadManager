import Foundation
import SDMCore
import SwiftUI

extension DownloadState {
    var title: String {
        switch self {
        case .created: "Created"
        case .probing: "Connecting"
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .pausing: "Pausing"
        case .paused: "Paused"
        case .retrying: "Retrying"
        case .finalizing: "Finalizing"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .created, .queued: "clock"
        case .probing: "network"
        case .downloading: "arrow.down.circle.fill"
        case .pausing: "pause.circle"
        case .paused: "pause.circle.fill"
        case .retrying: "arrow.clockwise.circle"
        case .finalizing: "shippingbox.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        case .paused, .pausing: .orange
        case .downloading, .probing, .retrying, .finalizing: .accentColor
        case .created, .queued: .secondary
        }
    }

    func allows(_ command: DownloadCommand) -> Bool {
        switch command {
        case .pause:
            [.queued, .downloading, .retrying].contains(self)
        case .resume:
            self == .paused
        case .cancel:
            self != .completed && self != .cancelled
        case .retry:
            self == .failed || self == .cancelled
        case .remove:
            [.completed, .failed, .cancelled, .paused].contains(self)
        }
    }
}

extension DownloadSnapshot {
    var displayFilename: String {
        if let destinationURL, !destinationURL.lastPathComponent.isEmpty {
            return destinationURL.lastPathComponent
        }
        if !filename.isEmpty {
            return filename
        }
        return sourceURL.lastPathComponent
    }

    var progressFraction: Double? {
        if state == .completed { return 1 }
        guard let contentLength, contentLength > 0 else { return nil }
        let boundedBytes = min(downloadedBytes, contentLength)
        return Double(boundedBytes) / Double(contentLength)
    }

    var availableCommands: [DownloadCommand] {
        DownloadCommand.allCases.filter(state.allows)
    }
}

extension Collection where Element == DownloadSnapshot {
    func commonCommands(for selectedIDs: Set<DownloadID>) -> [DownloadCommand] {
        guard !selectedIDs.isEmpty else { return [] }
        let selectedSnapshots = filter { selectedIDs.contains($0.id) }
        guard selectedSnapshots.count == selectedIDs.count else { return [] }
        return DownloadCommand.allCases.filter { command in
            selectedSnapshots.allSatisfy { $0.state.allows(command) }
        }
    }
}

extension DownloadSegmentSnapshot {
    var progressFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(min(downloadedBytes, totalBytes)) / Double(totalBytes)
    }
}

enum DownloadFormatting {
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(clamping: value),
            countStyle: .file
        )
    }

    static func speed(_ value: UInt64) -> String {
        guard value > 0 else { return "—" }
        return "\(bytes(value))/s"
    }

    static func duration(_ value: Duration?) -> String {
        guard let value else { return "—" }
        let seconds = max(value.components.seconds, 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}

struct PresentedDownloadError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, error: Error) {
        self.title = title
        message = DownloadService.message(for: error)
    }
}
