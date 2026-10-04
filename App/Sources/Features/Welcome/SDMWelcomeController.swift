#if os(macOS)
import SwiftUI
import WelcomeKit

@MainActor
final class SDMWelcomeController {
    private let launchState = WelcomeLaunchState()
    private let windowController = WelcomeWindowController()

    func presentIfNeeded(openMainWindow: @escaping () -> Void) {
        guard launchState.claimAutomaticPresentation() else { return }
        present(openMainWindow: openMainWindow)
    }

    func present(openMainWindow: @escaping () -> Void) {
        let controller = windowController
        let state = launchState
        let content = SDMWelcomeView(
            onFinish: { [weak controller] in
                controller?.close()
                openMainWindow()
            },
            onClose: { [weak controller] in controller?.close() }
        )
        .onAppear(perform: state.recordPresentation)

        controller.present(title: "Welcome to Swifty Download Manager", content: content)
    }
}
#endif
