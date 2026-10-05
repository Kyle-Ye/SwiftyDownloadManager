import SwiftUI

struct WelcomeCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Close Welcome", bundle: .module)
            } icon: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }
}
