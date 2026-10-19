import SwiftUI

/// A followed story's lines in its folder header: one status line, which opens the Following
/// sheet (a `HeaderLink`, its parts set apart by space and ink), and, while its site has asked to
/// slow down or isn't answering, one notice saying how long the next chapter waits, by its title.
///
/// ```
/// 📡 Following   fetching chapter text 4 of 107 ›
/// 📡 Following   1 chapter couldn’t load   fetched 41 of 107 ›
/// ⏳ Royal Road asked to slow down (429). “Chapter 42: Low Tide” in 1:52, then slower.
/// 📡 Following   checked today 8:02 AM   2 new ›
/// ```
struct FollowStatus: View {
    let folder: Folder
    /// The folder's pages, in its order.
    let pages: [Page]

    @Environment(FollowCenter.self) private var follow
    @Environment(ShellState.self) private var shell

    var body: some View {
        let progress = follow.progress(of: pages)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HeaderLink(symbol: Icons.follow, parts: parts(progress), identifier: "followStatus") {
                shell.present(.following(folder.id))
            }
            if let next = progress.fetching, let url = folder.contentsURL,
               let backOff = follow.queue.backOff(of: FetchQueue.site(of: url)) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NoticeCard(symbol: Icons.waiting,
                               text: FollowText.backOffNotice(site: TableOfContents.siteName(of: url), status: backOff.status,
                                                              chapter: next, wait: backOff.until.timeIntervalSince(context.date)),
                               identifier: "followBackOff")
                }
            }
        }
    }

    private func parts(_ progress: FollowCenter.Progress) -> [String] {
        let state = folder.followState
        var parts = [state?.isFollowing == false ? String(localized: "Not following") : String(localized: "Following")]
        // Ahead of the progress, which it matters more than: read first, and first on the line.
        if progress.failed > 0 { parts.append(FollowText.couldNotLoad(progress.failed)) }
        if let fetching = progress.fetching {
            parts.append(String(localized: "fetching chapter text \(fetching.number) of \(progress.chapters)"))
        } else if progress.toFetch > 0 {
            parts.append(String(localized: "fetched \(progress.withText) of \(progress.chapters)"))
        } else if follow.checking.contains(folder.id) {
            parts.append(String(localized: "checking for new chapters"))
        } else if state?.isFollowing == true, let checked = state?.lastCheckedAt {
            parts.append(String(localized: "checked \(FollowText.when(checked))"))
            if let added = state?.lastAddedAt, added == checked, let count = state?.lastAddedCount, count > 0 {
                parts.append(String(localized: "\(count) new"))
            }
        }
        return parts
    }
}

/// Follow's words, in one place: addresses shortened, times, and what a chapter waiting for its
/// text says in its row (a site's name is its contents reader's, `TableOfContents.siteName`).
@MainActor
enum FollowText {
    /// "…/chapter/900001/1-first-frost": the address's last three parts, or its host and
    /// path when it is shorter.
    static func shortAddress(_ url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count > 3 else { return ShellState.addressText(for: url) }
        return "…/" + parts.suffix(3).joined(separator: "/")
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

    /// The header's notice while a site backs off (`status` nil: it didn't answer), naming the
    /// chapter waiting by its title, or as the next chapter when it has none. The site's name can
    /// be a lowercase host ("example.com"); it is capitalized as the name it is.
    static func backOffNotice(site: String, status: Int?, chapter: FollowCenter.Progress.Fetching,
                              wait: TimeInterval) -> String {
        let site = site.prefix(1).uppercased() + site.dropFirst()
        let name = chapter.title.map { "“\($0)”" } ?? String(localized: "The next chapter")
        let after = countdown(wait)
        guard let status else {
            return String(localized: "\(site) isn’t answering. \(name) is tried again in \(after).")
        }
        return status == 429
            ? String(localized: "\(site) asked to slow down (429). \(name) in \(after), then slower.")
            : String(localized: "\(site) had a problem (\(status)). \(name) in \(after), then slower.")
    }

    /// "1 chapter couldn’t load", "3 chapters couldn’t load": the status line's part, and the
    /// Following sheet's.
    static func couldNotLoad(_ count: Int) -> String {
        count == 1 ? String(localized: "1 chapter couldn’t load") : String(localized: "\(count) chapters couldn’t load")
    }

    /// A followed story's chapter waiting for its text, as its row says it (`FollowCenter.status`):
    /// being fetched, retried after its site's back-off, waiting, or why it couldn't be had.
    static func rowNote(_ status: FollowCenter.ChapterStatus, now: Date) -> String {
        switch status {
        case .fetching: String(localized: "Fetching text…")
        case .retrying(let until): String(localized: "Retrying in \(countdown(until.timeIntervalSince(now)))")
        case .waiting: String(localized: "Waiting")
        case .failed(let message): message
        }
    }
}
