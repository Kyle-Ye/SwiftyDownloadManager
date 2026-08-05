/// The transport implementation used for a download.
public enum DownloadEngineKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case libcurl
    case urlSession

    public var id: Self { self }

    public var title: String {
        switch self {
        case .libcurl: "libcurl"
        case .urlSession: "URLSession"
        }
    }
}
