import SwiftUI
import WelcomeKit

/// Decorative illustrations stay in the host app; WelcomeKit owns only the tour UI.
struct SDMWelcomeArtwork: View {
    let page: WelcomePage

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        SDMWelcomeArtworkStyle.ink,
                        SDMWelcomeArtworkStyle.blue,
                        SDMWelcomeArtworkStyle.cyan,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: geometry.size.width * 0.92)
                    .offset(x: geometry.size.width * 0.29, y: geometry.size.height * 0.32)

                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.70)
                    .offset(x: -geometry.size.width * 0.28, y: -geometry.size.height * 0.43)

                switch SDMWelcomePageID(rawValue: page.id) {
                case .connections:
                    SDMWelcomeConnectionsArtwork(size: geometry.size)
                case .browsers:
                    SDMWelcomeBrowserArtwork(size: geometry.size)
                case .welcome, .none:
                    SDMWelcomeDownloadsArtwork(size: geometry.size)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Welcome artwork") {
    VStack(spacing: 12) {
        ForEach(SDMWelcomeContent.pages) { page in
            SDMWelcomeArtwork(page: page)
                .aspectRatio(SDMWelcomeArtworkStyle.aspectRatio, contentMode: .fit)
        }
    }
    .frame(width: 360)
    .padding()
}
#endif
