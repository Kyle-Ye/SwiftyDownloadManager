#if os(macOS)
import SwiftUI

struct LockScreenProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(progress, 0), 1))
            let fillWidth = fraction == 0
                ? 0
                : max(proxy.size.height, proxy.size.width * fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(tint)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 6)
    }
}

#if DEBUG
#Preview("Lock Screen Progress") {
    VStack {
        LockScreenProgressBar(progress: 0.17, tint: .orange.opacity(0.82))
        LockScreenProgressBar(progress: 0.72, tint: .accentColor)
    }
    .frame(width: 320)
    .padding()
}
#endif
#endif
