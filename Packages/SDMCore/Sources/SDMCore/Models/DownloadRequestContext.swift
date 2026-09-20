import Foundation

/// A browser cookie with its original scope. Never encoded in download history.
public struct DownloadCookie: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let secure: Bool
    public let hostOnly: Bool
    public let expirationDate: Double?

    public init(name: String, value: String, domain: String, path: String = "/",
                secure: Bool = true, hostOnly: Bool = true, expirationDate: Double? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.hostOnly = hostOnly
        self.expirationDate = expirationDate
    }

    func matches(_ url: URL, now: Date = .now) -> Bool {
        guard let host = url.host?.lowercased(),
              expirationDate.map({ $0 > now.timeIntervalSince1970 }) ?? true,
              !secure || url.scheme?.lowercased() == "https" else { return false }
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host == domain || (!hostOnly && host.hasSuffix("." + domain)) else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || (requestPath.hasPrefix(path) &&
            (path.hasSuffix("/") || requestPath.dropFirst(path.count).hasPrefix("/")))
    }

    var netscapeLine: String {
        [domain, hostOnly ? "FALSE" : "TRUE", path, secure ? "TRUE" : "FALSE",
         expirationDate.map { String(Int64($0)) } ?? "0", name, value].joined(separator: "\t")
    }
}

/// Transient authentication context. Codable is for private browser handoff only;
/// DownloadRequest deliberately excludes this value from its persisted form.
public struct DownloadRequestContext: Codable, Sendable, Equatable {
    public let cookies: [DownloadCookie]
    public let userAgent: String?
    public let referrer: URL?

    public init(cookies: [DownloadCookie] = [], userAgent: String? = nil, referrer: URL? = nil) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.referrer = referrer
    }

    func validate(for url: URL) throws {
        func safe(_ value: String) -> Bool {
            !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        }
        guard cookies.count <= 512,
              (userAgent.map { safe($0) && $0.utf8.count <= 2048 } ?? true),
              (referrer.map { safe($0.absoluteString) && ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.user == nil && $0.password == nil } ?? true),
              cookies.allSatisfy({ cookie in
                  !cookie.name.isEmpty && safe(cookie.name) && safe(cookie.value) &&
                  !cookie.name.contains(where: { "()<>@,;:\\\"/[]?={} ".contains($0) }) &&
                  !cookie.value.contains(";") && cookie.value.utf8.count <= 16384 &&
                  safe(cookie.domain) && !cookie.domain.isEmpty &&
                  !cookie.domain.contains(where: { "/: ".contains($0) }) &&
                  safe(cookie.path) && cookie.path.hasPrefix("/") &&
                  (cookie.expirationDate.map { $0.isFinite && $0 >= 0 && $0 < Double(Int64.max) } ?? true)
              }) else {
            throw DownloadError(code: .invalidArgument, message: "Browser request context is invalid.")
        }
        // An expired cookie may arrive during handoff. It is omitted, never revived.
        guard cookies.filter({ $0.expirationDate.map { $0 > Date.now.timeIntervalSince1970 } ?? true })
            .allSatisfy({ $0.matches(url) }) else {
            throw DownloadError(code: .invalidArgument, message: "Browser cookies do not match the download URL.")
        }
    }

    func referrerHeader(for url: URL) -> String? {
        guard let referrer, !(referrer.scheme == "https" && url.scheme != "https"),
              var components = URLComponents(url: referrer, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    var netscapeCookies: String {
        cookies.filter { $0.expirationDate.map { $0 > Date.now.timeIntervalSince1970 } ?? true }
            .map(\.netscapeLine).joined(separator: "\n")
    }

    /// Match again for every redirected request; never reuse a raw Cookie header.
    func cookieHeader(for url: URL) -> String? {
        let value = cookies.filter { $0.matches(url) }
            .sorted { $0.path.count > $1.path.count }
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return value.isEmpty ? nil : value
    }
}
