import Foundation

struct BrowserDownloadRequest: Equatable {
    static let callbackScheme = "swifty-download-manager"

    let url: URL
    let suggestedFilename: String?
    let sourcePageURL: URL?

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
        suggestedFilename = components.nonEmptyValue(forQueryItem: "filename")
        sourcePageURL = components
            .value(forQueryItem: "source")
            .flatMap(URL.init(string:))
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
