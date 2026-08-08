import Foundation

public enum SDMCoreBackgroundSessionEvents {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable () -> Void] = [:]

    public static func handle(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            handlers[identifier] = completionHandler
        }
    }

    static func finish(identifier: String) {
        let handler = lock.withLock {
            handlers.removeValue(forKey: identifier)
        }
        guard let handler else { return }
        Task { @MainActor in
            handler()
        }
    }
}
