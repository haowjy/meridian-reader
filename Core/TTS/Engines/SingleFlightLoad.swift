import Foundation

/// A host's model load, run once (`LocalSynthHost.prepare`): the first `run` starts it, later
/// callers await the same load. Cancelling a caller cancels the load, so Settings' cancel reaches
/// a prepare in flight. A load that failed or was cancelled runs again on the next `run`;
/// `reset` forgets a finished one (the host lost what it loaded). `close` ends it for good: the
/// load in flight is cancelled and waited for, and every later `run` throws, so a host being
/// unloaded can't finish loading behind its caller or load again.
final class SingleFlightLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    private var closed = false
    private var task: Task<Void, Error>?

    var isLoaded: Bool { lock.withLock { loaded } }

    func run(_ load: @escaping @Sendable () async throws -> Void) async throws {
        let task: Task<Void, Error>? = try lock.withLock {
            if closed { throw CancellationError() }
            if loaded { return nil }
            if let task { return task }
            let created = Task(operation: load)
            self.task = created
            return created
        }
        guard let task else { return }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            lock.withLock {
                guard self.task == task else { return }
                loaded = true
                self.task = nil
            }
        } catch {
            lock.withLock { if self.task == task { self.task = nil } }
            throw error
        }
    }

    func reset() {
        lock.withLock { loaded = false }
    }

    func close() async {
        let task: Task<Void, Error>? = lock.withLock {
            closed = true
            loaded = false
            defer { self.task = nil }
            return self.task
        }
        task?.cancel()
        _ = try? await task?.value
    }
}
