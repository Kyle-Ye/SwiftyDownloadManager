import Foundation
import SDMCore

extension Notification.Name {
    static let browserDownloadCallback = Notification.Name(
        "top.kyleye.swifty-download-manager.browser-callback"
    )
}

struct BrowserDownloadRequest: Equatable {
    static let callbackScheme = "swifty-download-manager"

    let url: URL
    let suggestedFilename: String?
    let sourcePageURL: URL?
    let requestContext: DownloadRequestContext?

    init?(callbackURL: URL) {
        guard callbackURL.scheme?.lowercased() == Self.callbackScheme,
              callbackURL.host?.lowercased() == "download",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let urlText = components.value(forQueryItem: "url"),
              let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }

        self.url = url
        requestContext = nil
        suggestedFilename = components.nonEmptyValue(forQueryItem: "filename")
        sourcePageURL = components
            .value(forQueryItem: "source")
            .flatMap(URL.init(string:))
    }
    init(payload data: Data) throws {
        struct Payload: Decodable {
            let url: URL
            let filename: String?
            let requestContext: DownloadRequestContext
        }
        guard data.count <= BrowserHandoffTicket.maximumPayloadSize else { throw BrowserHandoffError.invalidPayload }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard ["http", "https"].contains(payload.url.scheme?.lowercased() ?? ""),
              payload.url.host != nil, payload.url.user == nil, payload.url.password == nil else {
            throw BrowserHandoffError.invalidPayload
        }
        url = payload.url
        suggestedFilename = payload.filename
        sourcePageURL = payload.requestContext.referrer
        requestContext = payload.requestContext
    }

}

private extension URLComponents {
    func value(forQueryItem name: String) -> String? {
        queryItems?.first { $0.name == name }?.value
    }

    func nonEmptyValue(forQueryItem name: String) -> String? {
        guard let value = value(forQueryItem: name)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
