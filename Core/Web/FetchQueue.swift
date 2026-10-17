import Foundation
import Observation
import WebKit

/// Every page fetched out of sight goes through here, strictly one at a time: a story's table of
/// contents, a chapter's text, a review's preview, a download's link page. Each request waits for
/// the one before it and for its site's pause (`FetchPacing`): a few seconds normally, longer
/// after slow replies, backing off when the site refuses (429, 5xx) or doesn't answer. Of the
/// requests whose site is ready, one asked for by a tap (`Priority.user`) goes first, then the
/// oldest; while one site's pause runs, another site's request may go.
///
/// Nothing loads while the app is in the background (the hidden view needs the window, and
/// WebKit is suspended there): requests wait for the app to come to the front. A load the
/// background cut short is tried again then, and doesn't count against its site.
///
/// The loads are `URLPageFetcher`'s: a hidden web view with the browser's cookies, so a site you
/// are signed in to in the browser serves the same pages here.
@MainActor
@Observable
final class FetchQueue {
    enum Priority: Comparable {
        case background
        /// Asked for by a tap: first among the requests that are ready.
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

    /// A request waiting for its turn.
    private struct Waiter {
        let order: Int
        let priority: Priority
        let site: String
        let turn: CheckedContinuation<Void, Never>
    }

    /// By host (`site(of:)`).
    private(set) var sites: [String: SiteState] = [:]

    @ObservationIgnored private let fetcher: URLPageFetcher
    @ObservationIgnored private let runState: AppRunState
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var waiting: [Waiter] = []
    @ObservationIgnored private var nextOrder = 0
    @ObservationIgnored private var isBusy = false
    /// Wakes the queue when the earliest waiting site's pause is over.
    @ObservationIgnored private var wake: Task<Void, Never>?
    /// Times the app went to the background: a load that saw it change was cut short there.
    @ObservationIgnored private var backgroundings = 0
    @ObservationIgnored private var runStateObserver: NSObjectProtocol?

    init(schemeHandlers: [String: any WKURLSchemeHandler] = [:], runState: AppRunState = .shared,
         now: @escaping () -> Date = Date.init) {
        fetcher = URLPageFetcher(schemeHandlers: schemeHandlers)
        self.runState = runState
        self.now = now
        runStateObserver = NotificationCenter.default.addObserver(forName: AppRunState.didChange, object: runState,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runStateChanged() }
        }
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

    /// Waits for its turn (its site ready, the app in front), loads, and records how the site
    /// answered.
    private func run<T>(_ url: URL, priority: Priority, _ load: @escaping (URLPageFetcher) async throws -> T) async throws -> T {
        let site = Self.site(of: url)
        while true {
            await takeTurn(priority, site: site)
            defer { passTurn() }
            try Task.checkCancellation()
            let started = now()
            let backgroundingsBefore = backgroundings
            do {
                let result = try await load(fetcher)
                record(.answered(seconds: now().timeIntervalSince(started)), refusal: nil, for: site)
                return result
            } catch {
                // Cut short by the background: tried again in front, its site none the worse.
                if backgroundings != backgroundingsBefore || runState.phase == .background, !(error is CancellationError) {
                    continue
                }
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

    private func takeTurn(_ priority: Priority, site: String) async {
        await withCheckedContinuation { turn in
            waiting.append(Waiter(order: nextOrder, priority: priority, site: site, turn: turn))
            nextOrder += 1
            dispatch()
        }
    }

    private func passTurn() {
        isBusy = false
        dispatch()
    }

    /// Gives the turn to the best waiting request whose site is ready (a tap's first, then the
    /// oldest), with the app in front. When none is ready, wakes at the earliest site's ready time.
    private func dispatch() {
        guard !isBusy, runState.phase != .background, !waiting.isEmpty else { return }
        let at = now()
        let ready = waiting.indices.filter { readyAt(waiting[$0].site) <= at }
        if let best = ready.max(by: { a, b in
            waiting[a].priority != waiting[b].priority ? waiting[a].priority < waiting[b].priority
                : waiting[a].order > waiting[b].order
        }) {
            isBusy = true
            waiting.remove(at: best).turn.resume()
            return
        }
        guard let earliest = waiting.map({ readyAt($0.site) }).min() else { return }
        wake?.cancel()
        wake = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, earliest.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dispatch()
        }
    }

    private func readyAt(_ site: String) -> Date {
        sites[site]?.readyAt ?? .distantPast
    }

    private func runStateChanged() {
        if runState.phase == .background { backgroundings += 1 }
        dispatch()
    }
}
