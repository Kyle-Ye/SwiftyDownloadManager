#if os(macOS)
import AppKit

@MainActor
final class SDMApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleBrowserCallback(_:)),
            name: .browserDownloadCallback,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .browserDownloadCallback,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    @objc private func handleBrowserCallback(_ notification: Notification) {
        guard let callbackText = notification.object as? String,
              let callbackURL = URL(string: callbackText),
              callbackURL.scheme?.lowercased() == BrowserDownloadRequest.callbackScheme
        else {
            return
        }

        if callbackURL.host?.lowercased() == "open" {
            NSApplication.shared.activate()
        } else if BrowserDownloadRequest(callbackURL: callbackURL) != nil {
            NotificationCenter.default.post(
                name: .browserDownloadCallback,
                object: callbackURL
            )
        }
    }
}
#else
import SDMCore
import UIKit

@MainActor
final class SDMApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        SDMCoreBackgroundSessionEvents.handle(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}
#endif
