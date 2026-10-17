import Foundation
import WebKit

/// One navigation of a web view, awaited: the view's navigation delegate for that one load. The
/// wait ends when the page has loaded, its load failed, or WebKit's content process ended
/// (memory pressure, a crash), and when it is cancelled: the waiting task's cancellation, or
/// `cancel()` once its owner is done with the view.
@MainActor
final class NavigationWait: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError, Equatable {
        case loadFailed(String)
        case contentProcessTerminated

        var errorDescription: String? {
            switch self {
            case .loadFailed(let message): message
            case .contentProcessTerminated: String(localized: "The page stopped loading.")
            }
        }
    }

    private var continuation: CheckedContinuation<Void, Error>?
    /// The main document's reply, once it has come (its HTTP status and headers).
    private(set) var response: HTTPURLResponse?

    /// Starts the navigation (`start`, such as `view.load(_:)`) and returns once it has ended.
    func run(_ start: () -> Void) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                start()
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    /// The navigation is no longer wanted: a wait still running ends with `CancellationError`.
    func cancel() { finish(CancellationError()) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame { response = navigationResponse.response as? HTTPURLResponse }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(Failure.loadFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(Failure.loadFailed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(Failure.contentProcessTerminated)
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    // MARK: - Time limits

    /// `operation`'s result, or `timeout` thrown if `seconds` pass first, or `CancellationError`
    /// once the calling task is cancelled. WebKit's calls can't be cancelled, so the operation
    /// runs on and its late result is dropped; its owner ends what it waits on (`cancel()`).
    static func within<T>(_ seconds: TimeInterval, orThrow timeout: Error,
                          _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let answer = FirstAnswer<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                answer.wait(continuation)
                let timer = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    answer.give(.failure(timeout))
                }
                Task { @MainActor in
                    let result: Result<T, Error>
                    do { result = .success(try await operation()) } catch { result = .failure(error) }
                    timer.cancel()
                    answer.give(result)
                }
            }
        } onCancel: {
            Task { @MainActor in answer.give(.failure(CancellationError())) }
        }
    }

    /// Resumes its continuation with the first result given; later ones are dropped. A result
    /// given before the continuation arrives is kept for it.
    @MainActor
    private final class FirstAnswer<T> {
        private var continuation: CheckedContinuation<T, Error>?
        private var early: Result<T, Error>?
        private var answered = false

        nonisolated init() {}

        func wait(_ continuation: CheckedContinuation<T, Error>) {
            if let early {
                continuation.resume(with: early)
                self.early = nil
            } else {
                self.continuation = continuation
            }
        }

        func give(_ result: Result<T, Error>) {
            guard !answered else { return }
            answered = true
            if let continuation {
                continuation.resume(with: result)
                self.continuation = nil
            } else {
                early = result
            }
        }
    }
}
