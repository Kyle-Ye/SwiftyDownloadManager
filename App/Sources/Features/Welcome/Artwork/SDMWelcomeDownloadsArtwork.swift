import SwiftUI

struct SDMWelcomeDownloadsArtwork: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: size.height * 0.79, height: size.height * 0.79)

            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: size.height * 0.64, height: size.height * 0.64)

            Image("SDMWelcomeLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size.height * 0.47, height: size.height * 0.47)
                .shadow(color: SDMWelcomeArtworkStyle.ink.opacity(0.25), radius: size.height * 0.06, y: size.height * 0.04)
                .offset(y: -size.height * 0.04)

            SDMWelcomeTransferTile(symbol: "doc.fill", progress: 0.66, size: size)
                .rotationEffect(.degrees(-7))
                .offset(x: -size.width * 0.21, y: size.height * 0.24)

            SDMWelcomeTransferTile(symbol: "checkmark", progress: 1, size: size)
                .rotationEffect(.degrees(7))
                .offset(x: size.width * 0.22, y: size.height * 0.18)
        }
        .frame(width: size.width, height: size.height)
    }
}
