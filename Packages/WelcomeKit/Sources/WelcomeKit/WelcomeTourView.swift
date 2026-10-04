import SwiftUI

/// A banner-led welcome tour, presented in a window on macOS or a sheet on iOS.
///
/// Page copy carries the tour's accessible content; artwork is treated as decorative.
/// The host owns presentation, completion persistence, and any permissions or setup.
public struct WelcomeTourView<Artwork: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pagination: WelcomePagination

    private let pages: [WelcomePage]
    private let artwork: (WelcomePage) -> Artwork
    private let onFinish: () -> Void
    private let onClose: () -> Void

    public init(
        pages: [WelcomePage],
        @ViewBuilder artwork: @escaping (WelcomePage) -> Artwork,
        onFinish: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.pages = pages
        self.artwork = artwork
        self.onFinish = onFinish
        self.onClose = onClose
        _pagination = State(initialValue: WelcomePagination(pageCount: pages.count))
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    if pages.indices.contains(pagination.selectedIndex) {
                        let page = pages[pagination.selectedIndex]
                        WelcomePageContent(
                            page: page,
                            artwork: artwork(page),
                            artworkHeight: min(geometry.size.width / 1.6, max(120, geometry.size.height * 0.48), 320)
                        )
                        .transition(.opacity)
                    } else {
                        Text("Welcome", bundle: .module)
                            .font(.largeTitle.bold())
                            .padding(48)
                    }
                }
                .id(pagination.selectedIndex)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                WelcomeTourControls(
                    pagination: pagination,
                    onBack: goBack,
                    onContinue: advance
                )
            }
            .overlay(alignment: .topTrailing) {
                WelcomeCloseButton(action: onClose)
                    .padding(12)
            }
        }
        .background(.background)
        .onChange(of: pages.count) { _, newCount in
            pagination.updatePageCount(newCount)
        }
    }

    private func goBack() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            pagination.goBack()
        }
    }

    private func advance() {
        if pagination.isLastPage {
            onFinish()
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                _ = pagination.advance()
            }
        }
    }
}
