import SwiftUI

struct WelcomeTourControls: View {
    let pagination: WelcomePagination
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if pagination.pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pagination.pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == pagination.selectedIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: index == pagination.selectedIndex ? 22 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Page \(pagination.selectedIndex + 1) of \(pagination.pageCount)", bundle: .module))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    if pagination.canGoBack {
                        WelcomeBackButton(action: onBack)
                    }
                    Spacer(minLength: 20)
                    WelcomeContinueButton(isLastPage: pagination.isLastPage, action: onContinue)
                }
                VStack(spacing: 12) {
                    WelcomeContinueButton(isLastPage: pagination.isLastPage, action: onContinue)
                    if pagination.canGoBack {
                        WelcomeBackButton(action: onBack)
                    }
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(.background)
    }
}
