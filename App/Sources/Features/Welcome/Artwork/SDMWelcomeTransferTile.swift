import SwiftUI

struct SDMWelcomeTransferTile: View {
    let symbol: String
    let progress: CGFloat
    let size: CGSize

    var body: some View {
        HStack(spacing: size.height * 0.04) {
            Image(systemName: symbol)
                .font(.system(size: size.height * 0.065, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: size.height * 0.025) {
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: size.width * 0.11, height: size.height * 0.016)

                Capsule()
                    .fill(.white.opacity(0.20))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(SDMWelcomeArtworkStyle.highlight)
                            .frame(width: size.width * 0.15 * progress)
                    }
                    .frame(width: size.width * 0.15, height: size.height * 0.018)
            }
        }
        .padding(size.height * 0.055)
        .background(SDMWelcomeArtworkStyle.ink.opacity(0.42), in: .rect(cornerRadius: size.height * 0.045))
        .overlay {
            RoundedRectangle(cornerRadius: size.height * 0.045)
                .stroke(SDMWelcomeArtworkStyle.edge, lineWidth: 1)
        }
        .shadow(color: SDMWelcomeArtworkStyle.ink.opacity(0.12), radius: size.height * 0.03, y: size.height * 0.02)
    }
}
