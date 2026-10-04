import SwiftUI
import WelcomeKit

struct SDMWelcomeView: View {
    let onFinish: () -> Void
    let onClose: () -> Void

    var body: some View {
        WelcomeTourView(
            pages: SDMWelcomeContent.pages,
            artwork: { page in SDMWelcomeArtwork(page: page) },
            onFinish: onFinish,
            onClose: onClose
        )
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        #endif
    }
}

#Preview {
    SDMWelcomeView(onFinish: {}, onClose: {})
        .frame(width: 600, height: 660)
}
