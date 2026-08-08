/// User-presentable metadata and feature support for a transport engine.
public struct DownloadEngineDescriptor: Equatable, Identifiable, Sendable {
    public let kind: DownloadEngineKind
    public let version: String
    public let features: Set<DownloadFeature>
    public let maximumConnectionsPerDownload: Int

    public var id: DownloadEngineKind { kind }

    public init(
        kind: DownloadEngineKind,
        version: String,
        features: Set<DownloadFeature>,
        maximumConnectionsPerDownload: Int
    ) {
        self.kind = kind
        self.version = version
        self.features = features
        self.maximumConnectionsPerDownload = maximumConnectionsPerDownload
    }

    public func supports(_ feature: DownloadFeature) -> Bool {
        features.contains(feature)
    }
}
