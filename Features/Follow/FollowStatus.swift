import SwiftUI

/// A followed story's lines in its folder header: one status line, which opens the Following
/// sheet, and, while its site has asked to slow down or isn't answering, one notice saying how
/// long the next chapter waits.
///
/// ```
/// 📡 Following · fetching chapter text 4 of 107 ›
/// 📡 Following · fetched 41 of 107 ›
/// ⏳ Royal Road asked to slow down (429). Chapter 42 in 1:52, then slower.
/// 📡 Following · checked today 8:02 AM · 2 new ›
/// ```
struct FollowStatus: View {
    let folder: Folder
    /// The folder's pages, in its order.
    let pages: [Page]

    @Environment(FollowCenter.self) private var follow
    @Environment(ShellState.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HeaderLink(symbol: Icons.follow, text: line, identifier: "followStatus") {
                shell.present(.following(folder.id))
            }
            if let next = nextChapter, let url = folder.contentsURL,
               let backOff = follow.queue.backOff(of: FetchQueue.site(of: url)) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NoticeCard(symbol: Icons.waiting,
                               text: FollowText.backOffNotice(site: FollowText.siteName(of: url), status: backOff.status,
                                                              chapter: next, wait: backOff.until.timeIntervalSince(context.date)),
                               identifier: "followBackOff")
                }
            }
        }
    }

    /// The number of the chapter fetched next: the one being fetched, else the first waiting.
    private var nextChapter: Int? {
        let index = pages.firstIndex { follow.fetching.contains($0.listenKey) }
            ?? pages.firstIndex { $0.isLink && !$0.skipsInPlayback && follow.failures[$0.listenKey] == nil }
        return index.map { $0 + 1 }
    }

    private var line: String {
        let state = folder.followState
        var parts = [state?.isFollowing == false ? String(localized: "Not following") : String(localized: "Following")]
        let fetched = pages.filter { !$0.isLink }.count
        if let index = pages.firstIndex(where: { follow.fetching.contains($0.listenKey) }) {
            parts.append(String(localized: "fetching chapter text \(index + 1) of \(pages.count)"))
        } else if fetched < pages.count {
            parts.append(String(localized: "fetched \(fetched) of \(pages.count)"))
        } else if follow.checking.contains(folder.id) {
            parts.append(String(localized: "checking for new chapters"))
        } else if state?.isFollowing == true, let checked = state?.lastCheckedAt {
            parts.append(String(localized: "checked \(FollowText.when(checked))"))
            if let added = state?.lastAddedAt, added == checked, let count = state?.lastAddedCount, count > 0 {
                parts.append(String(localized: "\(count) new"))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Follow's words, in one place: addresses shortened, sites named, times, and what a chapter
/// waiting for its text says in its row.
@MainActor
enum FollowText {
    /// "…/chapter/301778/1-good-morning-brother": the address's last three parts, or its host and
    /// path when it is shorter.
    static func shortAddress(_ url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count > 3 else { return ShellState.addressText(for: url) }
        return "…/" + parts.suffix(3).joined(separator: "/")
    }

    /// "Royal Road", else the host without "www.".
    static func siteName(of url: URL) -> String {
        let host = url.host?.lowercased() ?? url.absoluteString
        if host == "royalroad.com" || host.hasSuffix(".royalroad.com") { return "Royal Road" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "today 8:02 AM", "yesterday 9:15 PM", "tomorrow 8:02 AM", else "14 Oct 8:02 AM".
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "yesterday \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow \(time)")
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// "1:52", "12:05".
    static func countdown(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The header's notice while a site backs off (`status` nil: it didn't answer).
    static func backOffNotice(site: String, status: Int?, chapter: Int, wait: TimeInterval) -> String {
        let after = countdown(wait)
        guard let status else {
            return String(localized: "\(site) isn’t answering. Chapter \(chapter) is tried again in \(after).")
        }
        return status == 429
            ? String(localized: "\(site) asked to slow down (429). Chapter \(chapter) in \(after), then slower.")
            : String(localized: "\(site) had a problem (\(status)). Chapter \(chapter) in \(after), then slower.")
    }

    /// A followed story's chapter waiting for its text, as its row says it: being fetched (or
    /// retried after its site's back-off), waiting, or why it couldn't be had. nil for a page
    /// with text, a link anywhere else, or a skipped chapter.
    static func rowNote(of page: Page, follow: FollowCenter, now: Date) -> String? {
        guard page.isWaitingChapter, !page.skipsInPlayback else { return nil }
        let key = page.listenKey
        if follow.fetching.contains(key) {
            if let url = page.url, let backOff = follow.queue.backOff(of: FetchQueue.site(of: url)) {
                return String(localized: "Retrying in \(countdown(backOff.until.timeIntervalSince(now)))")
            }
            return String(localized: "Fetching text…")
        }
        if let failure = follow.failures[key] { return failure }
        return String(localized: "Waiting")
    }
}
