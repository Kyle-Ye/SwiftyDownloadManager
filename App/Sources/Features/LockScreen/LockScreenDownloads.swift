#if os(macOS)
import SDMCore

enum LockScreenDownloads {
    static let maximumVisibleCount = 4

    static func select(
        from snapshots: [DownloadSnapshot],
        limit: Int = maximumVisibleCount
    ) -> [DownloadSnapshot] {
        guard limit > 0 else { return [] }
        return Array(
            snapshots
                .filter { $0.state.appearsOnLockScreen }
                .sortedForDownloadList()
                .prefix(limit)
        )
    }
}

extension DownloadState {
    var appearsOnLockScreen: Bool {
        switch self {
        case .created, .probing, .queued, .downloading, .pausing, .paused,
             .retrying, .finalizing:
            true
        case .completed, .failed, .cancelled:
            false
        }
    }
}
#endif
