#if os(macOS)
import SwiftUI

struct BrowserFeatureRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .font(.callout)
    }
}
#endif
