#if os(macOS)
import SwiftUI

struct BrowserExtensionStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsProgress = false

    var body: some View {
        HStack(spacing: BrowserExtensionDesign.compactSpacing) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(title)
        }
        .font(.caption)
        .bold()
        .foregroundStyle(tint)
        .padding(.horizontal, BrowserExtensionDesign.inlineSpacing)
        .padding(.vertical, BrowserExtensionDesign.compactSpacing)
        .background(
            tint.opacity(0.12),
            in: .capsule
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(title)")
    }
}
#endif
