#if os(macOS)
import SwiftUI

struct WelcomeLaunchModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let controller: SDMWelcomeController

    func body(content: Content) -> some View {
        content.task {
            controller.presentIfNeeded {
                openWindow(id: AppWindowID.main)
            }
        }
    }
}
#endif
