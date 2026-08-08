import SDMCore

enum RecentDownloads {
    static let maximumCount = 8

    static func select(
        from snapshots: [DownloadSnapshot],
        limit: Int = maximumCount
    ) -> [DownloadSnapshot] {
        guard limit > 0 else { return [] }
        return Array(snapshots.sorted(by: isOrderedBefore).prefix(limit))
    }

    private static func isOrderedBefore(
        _ lhs: DownloadSnapshot,
        _ rhs: DownloadSnapshot
    ) -> Bool {
        if lhs.state.isActiveForMenuBar != rhs.state.isActiveForMenuBar {
            return lhs.state.isActiveForMenuBar
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.description < rhs.id.description
    }
}

extension DownloadState {
    var isActiveForMenuBar: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            false
        case .created, .probing, .queued, .downloading, .pausing, .paused,
             .retrying, .finalizing:
            true
        }
    }

    var showsIndeterminateMenuBarProgress: Bool {
        switch self {
        case .probing, .downloading, .retrying, .finalizing:
            true
        case .created, .queued, .pausing, .paused, .completed, .failed, .cancelled:
            false
        }
    }
}
