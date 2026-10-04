import SwiftUI

struct WelcomeContinueButton: View {
    let isLastPage: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLastPage {
                    Text("Get Started", bundle: .module)
                } else {
                    Text("Continue", bundle: .module)
                }
            }
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(minWidth: 120, minHeight: 24)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
}
