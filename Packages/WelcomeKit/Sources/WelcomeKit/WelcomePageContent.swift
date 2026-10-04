import SwiftUI

struct WelcomePageContent<Artwork: View>: View {
    let page: WelcomePage
    let artwork: Artwork
    let artworkHeight: Double

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .frame(maxWidth: .infinity)
                .frame(height: artworkHeight)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
    }
}
