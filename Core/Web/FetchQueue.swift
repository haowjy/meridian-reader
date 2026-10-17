import Foundation
import Observation
import WebKit

/// Every page fetched out of sight goes through here, strictly one at a time: a story's table of
/// contents, a chapter's text, a review's preview, a download's link page. Each request waits for
/// the one before it and then for its site's pause (`FetchPacing`): a few seconds normally, longer
/// after slow replies, backing off when the site refuses (429, 5xx) or doesn't answer. A request
/// asked for by a tap (`Priority.user`) goes before background work waiting its turn, never
/// before the pause. While a site's pause runs, another site's request may go.
///
/// The loads are `URLPageFetcher`'s: a hidden web view with the browser's cookies, so a site you
/// are signed in to in the browser serves the same pages here.
@MainActor
@Observable
final class FetchQueue {
    enum Priority: Comparable {
        case background
        /// Asked for by a tap: first in line.
        case user
    }

    /// Where a site stands between requests.
    struct SiteState: Equatable {
        var pacing = FetchPacing()
        /// When its next request may go.
        var readyAt: Date = .distantPast
        /// The last refusal's HTTP status (nil: no answer at all), while backing off.
        var refusal: Int?
    }

    /// By host (`site(of:)`).
    private(set) var sites: [String: SiteState] = [:]
    /// The address loading now.
    private(set) var loading: URL?

    @ObservationIgnored private let fetcher: URLPageFetcher
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var waiting: [(priority: Priority, turn: CheckedContinuation<Void, Never>)] = []

    init(schemeHandlers: [String: any WKURLSchemeHandler] = [:], now: @escaping () -> Date = Date.init) {
        fetcher = URLPageFetcher(schemeHandlers: schemeHandlers)
        self.now = now
    }

    /// The page at `url`, extracted.
    func content(of url: URL, priority: Priority) async throws -> PageContent {
        try await run(url, priority: priority) { try await $0.content(of: url) }
    }

    /// The links of the page at `url`.
    func links(of url: URL, priority: Priority) async throws -> LinkPage {
        try await run(url, priority: priority) { try await $0.links(of: url) }
    }

    /// The site a request to `url` is paced as.
    nonisolated static func site(of url: URL) -> String {
        url.host?.lowercased() ?? url.scheme ?? ""
    }

    /// The site's back-off, while it lasts: until when, and the refusal's status (nil: no answer).
    func backOff(of site: String) -> (until: Date, status: Int?)? {
        guard let state = sites[site], state.pacing.isBackingOff, state.readyAt > now() else { return nil }
        return (state.readyAt, state.refusal)
    }

    /// Waits for its turn and its site's pause, loads, and records how the site answered.
    private func run<T>(_ url: URL, priority: Priority, _ load: @escaping (URLPageFetcher) async throws -> T) async throws -> T {
        let site = Self.site(of: url)
        while true {
            await takeTurn(priority)
            let wait = (sites[site]?.readyAt ?? .distantPast).timeIntervalSince(now())
            guard wait <= 0 else {
                // The site's pause: another site's request may go meanwhile.
                passTurn()
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            defer { passTurn() }
            try Task.checkCancellation()
            loading = url
            defer { loading = nil }
            let started = now()
            do {
                let result = try await load(fetcher)
                record(.answered(seconds: now().timeIntervalSince(started)), refusal: nil, for: site)
                return result
            } catch {
                if let outcome = Self.outcome(of: error, after: now().timeIntervalSince(started)) {
                    record(outcome, refusal: Self.status(of: error), for: site)
                }
                throw error
            }
        }
    }

    private func record(_ outcome: FetchPacing.Outcome, refusal: Int?, for site: String) {
        var state = sites[site] ?? SiteState()
        state.pacing.record(outcome)
        state.readyAt = now().addingTimeInterval(state.pacing.delay)
        state.refusal = state.pacing.isBackingOff ? refusal : nil
        sites[site] = state
    }

    /// How a failed request counts for its site's pace: a refusal (429, 5xx), no answer (the load
    /// failed or timed out), or an answer (another HTTP error, a page with nothing to extract).
    /// nil when the site had no part in it: cancelled, or no window to load in.
    nonisolated static func outcome(of error: Error, after seconds: TimeInterval) -> FetchPacing.Outcome? {
        switch error {
        case URLPageFetcher.FetchError.status(let code, let retryAfter):
            return code == 429 || code >= 500 ? .refused(retryAfter: retryAfter) : .answered(seconds: seconds)
        case URLPageFetcher.FetchError.noWindow, is CancellationError:
            return nil
        case URLPageFetcher.FetchError.timedOut(let stage) where stage == .load:
            return .noAnswer
        case is NavigationWait.Failure:
            return .noAnswer
        default:
            return .answered(seconds: seconds)
        }
    }

    private nonisolated static func status(of error: Error) -> Int? {
        if case URLPageFetcher.FetchError.status(let code, _) = error { return code }
        return nil
    }

    // MARK: - One at a time

    private func takeTurn(_ priority: Priority) async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append((priority, $0)) }
    }

    /// The next turn goes to the first waiting request of the highest priority.
    private func passTurn() {
        guard let best = waiting.indices.max(by: { waiting[$0].priority < waiting[$1].priority || ($0 > $1 && waiting[$0].priority == waiting[$1].priority) })
        else {
            isBusy = false
            return
        }
        waiting.remove(at: best).turn.resume()
    }
}
