import Foundation

struct URLSessionDownloadRecord: Codable, Sendable {
    let request: DownloadRequest
    var snapshot: DownloadSnapshot
    var resumeData: Data?
    var events: [DownloadDiagnosticEvent]
}
