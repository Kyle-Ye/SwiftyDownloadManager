enum DownloadInfoSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case connections = "Connections"
    case log = "Log"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .log: "list.bullet.rectangle"
        }
    }
}
