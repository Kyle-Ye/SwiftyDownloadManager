#if os(macOS)
import Foundation

enum BrowserExtensionDesign {
    static let minimumWindowWidth = 700.0
    static let minimumWindowHeight = 450.0
    static let pagePadding = 24.0
    static let sectionSpacing = 18.0
    static let cardPadding = 18.0
    static let cardSpacing = 14.0
    static let featureSpacing = 8.0
    static let compactSpacing = 4.0
    static let inlineSpacing = 8.0
    static let wideSpacing = 24.0
    static let headerSpacing = 12.0
    static let cardRadius = 14.0
    static let headerIconRadius = 12.0
    static let headerIconSize = 48.0
    static let browserIconRadius = 11.0
    static let browserIconSize = 46.0
    static let cardContentInset = browserIconSize + cardSpacing
}
#endif
