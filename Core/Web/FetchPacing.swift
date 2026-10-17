import Foundation

/// How long the fetch queue (`FetchQueue`) waits before its next request to one site, from how the
/// site answered the last one. Pure, so it is tested without a network.
///
/// - **A pause between requests**: `pause` (4 s), or `slowPause` (12 s) after a reply that took
///   `slowReply` (6 s) or more.
/// - **Backing off**: a refusal (429, or a 5xx) or no answer at all (a failed load, a timeout)
///   doubles the wait, from `firstBackOff` (1 min) up to `maxBackOff` (30 min), and never less
///   than a refusal's `Retry-After`.
/// - **Easing back**: each answer halves the wait, down to the pause again, so after a back-off
///   the queue goes on slower before it is back to its pace.
struct FetchPacing: Equatable {
    static let pause: TimeInterval = 4
    static let slowPause: TimeInterval = 12
    static let slowReply: TimeInterval = 6
    static let firstBackOff: TimeInterval = 60
    static let maxBackOff: TimeInterval = 30 * 60

    enum Outcome: Equatable {
        /// The site answered (a page, or a refusal that isn't about the pace, such as a 404),
        /// after `seconds`.
        case answered(seconds: TimeInterval)
        /// The site asked to slow down (429) or couldn't answer (5xx); `retryAfter`: its
        /// `Retry-After`, in seconds.
        case refused(retryAfter: TimeInterval?)
        /// No answer: the load failed or timed out.
        case noAnswer
    }

    /// The wait before the next request to the site.
    private(set) var delay: TimeInterval = Self.pause
    /// The last request was refused or got no answer: `delay` is a back-off.
    private(set) var isBackingOff = false

    mutating func record(_ outcome: Outcome) {
        switch outcome {
        case .answered(let seconds):
            isBackingOff = false
            delay = max(seconds >= Self.slowReply ? Self.slowPause : Self.pause, delay / 2)
        case .refused(let retryAfter):
            backOff(atLeast: retryAfter ?? 0)
        case .noAnswer:
            backOff(atLeast: 0)
        }
    }

    private mutating func backOff(atLeast floor: TimeInterval) {
        isBackingOff = true
        delay = min(Self.maxBackOff, max(Self.firstBackOff, delay * 2, floor))
    }

    /// A `Retry-After` header's wait in seconds: a number of seconds, or an HTTP date (`now` is
    /// when the reply came). nil when there is none or it can't be read.
    static func retryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = TimeInterval(header) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header).map { max(0, $0.timeIntervalSince(now)) }
    }
}
