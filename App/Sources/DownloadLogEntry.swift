import Foundation

struct DownloadLogEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: DownloadLogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: DownloadLogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}
