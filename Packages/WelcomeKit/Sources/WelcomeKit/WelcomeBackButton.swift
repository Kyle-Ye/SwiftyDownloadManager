import SwiftUI

struct WelcomeBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Back", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(minHeight: 24)
        }
        .buttonStyle(.bordered)
    }
}
