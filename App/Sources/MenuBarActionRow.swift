import SwiftUI

struct MenuBarActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(isHovered ? 0.07 : 0),
            in: .rect(cornerRadius: 6)
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}
