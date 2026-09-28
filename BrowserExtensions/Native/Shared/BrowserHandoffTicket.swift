import CryptoKit
import Foundation

/// One-use transport key delivered through OS app activation, separately from
/// the encrypted browser payload. Never put a ticket in a page's DOM.
struct BrowserHandoffTicket: Sendable {
    let id: UUID
    let keyData: Data
    let browser: String
    static let maximumPayloadSize = 96 * 1024
    static let lifetime: TimeInterval = 60

    init(browser: String) {
        id = UUID()
        keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        self.browser = browser
    }

    init?(callbackURL: URL) {
        guard callbackURL.scheme == "swifty-download-manager", callbackURL.host == "handoff",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 3,
              Set(items.map(\.name)) == Set(["id", "key", "browser"]),
              let idText = items.first(where: { $0.name == "id" })?.value, let id = UUID(uuidString: idText),
              let keyText = items.first(where: { $0.name == "key" })?.value,
              let key = Data(base64Encoded: keyText), key.count == 32,
              let browser = items.first(where: { $0.name == "browser" })?.value,
              ["chrome", "safari"].contains(browser) else { return nil }
        self.id = id
        keyData = key
        self.browser = browser
    }

    var callbackURL: URL {
        var components = URLComponents()
        components.scheme = "swifty-download-manager"
        components.host = "handoff"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString.lowercased()),
            URLQueryItem(name: "key", value: keyData.base64EncodedString()),
            URLQueryItem(name: "browser", value: browser)]
        // All components above are constructed locally and have fixed valid forms.
        guard let url = components.url else { preconditionFailure("Invalid locally constructed handoff URL") }
        return url
    }

    func seal(_ data: Data) throws -> Data {
        guard data.count <= Self.maximumPayloadSize else { throw BrowserHandoffError.invalidPayload }
        let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: keyData),
            authenticating: Data(id.uuidString.lowercased().utf8))
        guard let combined = sealed.combined else { throw BrowserHandoffError.invalidPayload }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        guard data.count <= Self.maximumPayloadSize + 28 else { throw BrowserHandoffError.invalidPayload }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: keyData),
            authenticating: Data(id.uuidString.lowercased().utf8))
    }
}
