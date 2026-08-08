#if os(macOS)
import SwiftUI

struct BrowserExtensionIcon: View {
    let applicationIcon: NSImage?
    let placeholderSystemImage: String

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: BrowserExtensionDesign.browserIconRadius)
                        .fill(.quaternary)

                    Image(systemName: placeholderSystemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(
            width: BrowserExtensionDesign.browserIconSize,
            height: BrowserExtensionDesign.browserIconSize
        )
        .accessibilityHidden(true)
    }
}
#endif
