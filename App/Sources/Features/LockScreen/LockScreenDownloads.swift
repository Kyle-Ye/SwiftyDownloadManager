#if os(macOS)
import SDMCore

enum LockScreenDownloads {
    static func select(
        from snapshots: [DownloadSnapshot],
        limit: Int = RecentDownloads.defaultMaximumCount
    ) -> [DownloadSnapshot] {
        RecentDownloads.select(from: snapshots, limit: limit)
    }
}
#endif
