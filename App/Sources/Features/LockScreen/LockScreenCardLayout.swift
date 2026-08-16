#if os(macOS)
import CoreGraphics

enum LockScreenCardLayout {
    static let widthRatio: CGFloat = 0.42
    static let widthToScreenHeightRatio: CGFloat = 0.72
    static let absoluteMaximumWidth: CGFloat = 720
    static let maximumHeightRatio: CGFloat = 0.52

    private static let fixedContentHeightBudget: CGFloat = 104
    private static let downloadRowHeightBudget: CGFloat = 65

    static func width(for screenSize: CGSize) -> CGFloat {
        min(
            screenSize.width * widthRatio,
            screenSize.height * widthToScreenHeightRatio,
            absoluteMaximumWidth
        )
    }

    static func maximumHeight(for screenSize: CGSize) -> CGFloat {
        screenSize.height * maximumHeightRatio
    }

    static func visibleDownloadLimit(
        requestedLimit: Int,
        screenSize: CGSize
    ) -> Int {
        guard requestedLimit > 0 else { return 0 }
        let availableRowsHeight = max(
            maximumHeight(for: screenSize) - fixedContentHeightBudget,
            downloadRowHeightBudget
        )
        let screenLimit = max(1, Int(availableRowsHeight / downloadRowHeightBudget))
        return min(requestedLimit, screenLimit)
    }
}
#endif
