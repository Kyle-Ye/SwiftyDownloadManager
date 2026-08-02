import Foundation

public enum DownloadErrorCode: UInt32, Sendable, Codable, CaseIterable {
    case invalidArgument = 1
    case notFound = 2
    case invalidState = 3
    case inputOutput = 4
    case network = 5
    case protocolViolation = 6
    case persistence = 7
    case shuttingDown = 8
    case internalFailure = 9
}

public struct DownloadError: Error, Sendable, Codable, Equatable {
    public let code: DownloadErrorCode
    public let message: String

    public init(code: DownloadErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
