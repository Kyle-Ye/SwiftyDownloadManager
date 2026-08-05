#if os(macOS)
import AppKit

@MainActor
final class SDMApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
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
