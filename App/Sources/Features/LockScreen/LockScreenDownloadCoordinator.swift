#if os(macOS)
import AppKit
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenDownloadCoordinator: NSObject {
    private static let screenDidLockNotification = Notification.Name(
        "com.apple.screenIsLocked"
    )
    private static let screenDidUnlockNotification = Notification.Name(
        "com.apple.screenIsUnlocked"
    )

    private let service: DownloadService
    private let userDefaults: UserDefaults
    private var overlayWindows: [NSWindow] = []
    private var isEnabled: Bool
    private var isScreenLocked = false
    private var isStopped = false

    init(
        service: DownloadService,
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.userDefaults = userDefaults
        isEnabled = userDefaults.bool(
            forKey: AppStorageKey.showsLockScreenDownloadStatus
        )
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenDidLock(_:)),
            name: Self.screenDidLockNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenDidUnlock(_:)),
            name: Self.screenDidUnlockNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil,
        )
    }

    @objc nonisolated private func handleScreenDidLock(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.screenDidLock()
        }
    }

    @objc nonisolated private func handleScreenDidUnlock(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.screenDidUnlock()
        }
    }

    @objc nonisolated private func handleDefaultsDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.defaultsDidChange()
        }
    }

    @objc nonisolated private func handleScreenParametersDidChange(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.screenParametersDidChange()
        }
    }

    @objc nonisolated private func handleApplicationWillTerminate(
        _ notification: Notification
    ) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    private func screenDidLock() {
        isScreenLocked = true
        updateOverlayWindows()
    }

    private func screenDidUnlock() {
        isScreenLocked = false
        closeOverlayWindows()
    }

    private func defaultsDidChange() {
        let nextValue = userDefaults.bool(
            forKey: AppStorageKey.showsLockScreenDownloadStatus
        )
        guard nextValue != isEnabled else { return }
        isEnabled = nextValue
        updateOverlayWindows()
    }

    private func screenParametersDidChange() {
        guard isEnabled, isScreenLocked else { return }
        updateOverlayWindows()
    }

    private func updateOverlayWindows() {
        closeOverlayWindows()
        guard !isStopped, isEnabled, isScreenLocked else { return }
        overlayWindows = NSScreen.screens.map(makeOverlayWindow)
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.canBecomeVisibleWithoutLogin = true
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.level = .init(rawValue: Int(Int32.max - 2))
        window.contentView = LockScreenOverlayContentView(service: service)

        SkyLightOperator.shared.delegateWindow(window)
        window.orderFrontRegardless()
        return window
    }

    private func closeOverlayWindows() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }

    private func stop() {
        guard !isStopped else { return }
        isStopped = true
        closeOverlayWindows()
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
