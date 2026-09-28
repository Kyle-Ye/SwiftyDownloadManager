import Foundation

enum BrowserHandoffError: LocalizedError {
    case invalidPayload
    case unavailable
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "The browser download could not be verified. Send it from the browser again."
        case .unavailable: "The browser connection is unavailable. Open SDM and send the download again."
        case .expired: "The browser handoff expired. Send the download from the browser again."
        }
    }
}
