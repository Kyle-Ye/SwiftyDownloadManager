#if os(macOS)
import SwiftUI

/// Own one instance for the lifetime of the macOS host that presents the welcome tour.
@MainActor
public final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    public override init() {
        super.init()
    }

    /// Creates a nonmodal welcome window, or brings the current tour forward.
    ///
    /// Repeated calls preserve the current content and page. `onClose` is invoked
    /// once whenever the window closes, including through `close()` or Command-W.
    /// Capture the controller or its owner weakly in callbacks to avoid cycles.
    public func present<Content: View>(
        title: String,
        content: Content,
        onClose: (() -> Void)? = nil
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let screen = NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(
            width: min(640, max(1, visibleFrame.width - 32)),
            height: min(650, max(1, visibleFrame.height - 32))
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.animationBehavior = .documentWindow
        window.contentView = NSHostingView(rootView: content.ignoresSafeArea(.container, edges: .top))
        window.delegate = self

        self.window = window
        self.onClose = onClose
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        let callback = onClose
        onClose = nil
        window = nil
        closingWindow.delegate = nil
        closingWindow.contentView = nil
        callback?()
    }
}
#endif
