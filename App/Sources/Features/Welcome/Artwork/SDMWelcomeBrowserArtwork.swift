import SwiftUI

struct SDMWelcomeBrowserArtwork: View {
    let size: CGSize

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: size.width * 0.014) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size.height * 0.034))
                    Capsule()
                        .fill(.white.opacity(0.50))
                        .frame(width: size.width * 0.19, height: size.height * 0.014)
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(size.height * 0.048)
                .background(.white.opacity(0.10))

                HStack(spacing: size.width * 0.045) {
                    Image(systemName: "safari")
                        .font(.system(size: size.height * 0.21, weight: .light))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: size.height * 0.035) {
                        Capsule()
                            .fill(.white.opacity(0.80))
                            .frame(width: size.width * 0.16, height: size.height * 0.018)
                        Capsule()
                            .fill(.white.opacity(0.30))
                            .frame(width: size.width * 0.12, height: size.height * 0.014)
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: size.height * 0.07, weight: .semibold))
                            .foregroundStyle(SDMWelcomeArtworkStyle.highlight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: size.width * 0.60, height: size.height * 0.59)
            .background(SDMWelcomeArtworkStyle.ink.opacity(0.28), in: .rect(cornerRadius: size.height * 0.055))
            .clipShape(.rect(cornerRadius: size.height * 0.055))
            .overlay {
                RoundedRectangle(cornerRadius: size.height * 0.055)
                    .stroke(SDMWelcomeArtworkStyle.edge, lineWidth: 1)
            }
            .rotationEffect(.degrees(-5))
            .offset(x: -size.width * 0.05, y: -size.height * 0.045)

            Image("SDMWelcomeLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size.height * 0.30, height: size.height * 0.30)
                .rotationEffect(.degrees(8))
                .shadow(color: SDMWelcomeArtworkStyle.ink.opacity(0.22), radius: size.height * 0.04, y: size.height * 0.025)
                .offset(x: size.width * 0.24, y: size.height * 0.22)
        }
        .frame(width: size.width, height: size.height)
    }
}
