/// Optional behavior that varies between transport engines.
public enum DownloadFeature: String, CaseIterable, Codable, Identifiable, Sendable {
    case backgroundTransfers
    case bandwidthLimiting
    case bundledCertificateAuthorities
    case multiConnectionTransfers
    case persistentRecovery
    case systemTrustStore

    public var id: Self { self }

    public var title: String {
        switch self {
        case .backgroundTransfers: "Background transfers"
        case .bandwidthLimiting: "Bandwidth limits"
        case .bundledCertificateAuthorities: "Bundled certificate authorities"
        case .multiConnectionTransfers: "Multi-connection transfers"
        case .persistentRecovery: "Persistent recovery"
        case .systemTrustStore: "System trust store"
        }
    }
}
