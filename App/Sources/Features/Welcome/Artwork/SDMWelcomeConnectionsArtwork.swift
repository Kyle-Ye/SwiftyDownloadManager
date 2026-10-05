import SwiftUI

struct SDMWelcomeConnectionsArtwork: View {
    let size: CGSize

    var body: some View {
        VStack(spacing: size.height * 0.045) {
            Image(systemName: "cloud.fill")
                .font(.system(size: size.height * 0.20))
                .foregroundStyle(.white)

            HStack(spacing: size.width * 0.12) {
                ForEach(0..<3) { _ in
                    VStack(spacing: size.height * 0.025) {
                        Capsule()
                            .fill(.white.opacity(0.45))
                            .frame(width: size.height * 0.006, height: size.height * 0.075)
                        Image(systemName: "arrow.down")
                            .font(.system(size: size.height * 0.055, weight: .semibold))
                            .foregroundStyle(SDMWelcomeArtworkStyle.highlight)
                    }
                }
            }

            HStack(spacing: size.width * 0.016) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(.white.opacity(0.17))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(SDMWelcomeArtworkStyle.highlight)
                                .frame(width: size.width * [0.13, 0.085, 0.11][index])
                        }
                        .frame(width: size.width * 0.16, height: size.height * 0.035)
                }
            }
            .padding(size.height * 0.045)
            .background(SDMWelcomeArtworkStyle.glass, in: .capsule)
            .overlay {
                Capsule().stroke(SDMWelcomeArtworkStyle.edge, lineWidth: 1)
            }

            HStack(spacing: size.width * 0.035) {
                Image(systemName: "pause.fill")
                Image(systemName: "play.fill")
            }
            .font(.system(size: size.height * 0.055, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.top, size.height * 0.01)
        }
        .frame(width: size.width, height: size.height)
    }
}
