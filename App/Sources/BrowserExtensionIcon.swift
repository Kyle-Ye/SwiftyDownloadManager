#if os(macOS)
import SwiftUI

struct BrowserExtensionIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrowserExtensionDesign.browserIconRadius)
                .fill(tint.gradient)

            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
        }
        .frame(
            width: BrowserExtensionDesign.browserIconSize,
            height: BrowserExtensionDesign.browserIconSize
        )
        .accessibilityHidden(true)
    }
}
#endif
