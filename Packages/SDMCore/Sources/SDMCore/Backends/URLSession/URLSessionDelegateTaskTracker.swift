import Foundation

/// Tracks terminal delegate work that must finish before iOS suspends a
/// background URLSession wake.
final class URLSessionDelegateTaskTracker: @unchecked Sendable {
    typealias Operation = @Sendable () async -> Void

    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func start(_ operation: @escaping Operation) {
        let token = UUID()
        let task = Task {
            await operation()
        }
        lock.withLock {
            tasks[token] = task
        }
        Task { [weak self] in
            await task.value
            self?.remove(token)
        }
    }

    func waitForTrackedTasks() async {
        let pendingTasks = lock.withLock {
            Array(tasks.values)
        }
        for task in pendingTasks {
            await task.value
        }
    }

    private func remove(_ token: UUID) {
        lock.withLock {
            tasks[token] = nil
        }
    }
}
