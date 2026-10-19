import Foundation
import SwiftData

/// Bounded Browse history entry (not a tab, not a Saved article).
@Model
final class RecentVisit {
    static let maxEntries = 30

    @Attribute(.unique) var id: UUID
    /// The page's canonical URL (`ArticleIdentity`): one visit per page.
    var urlString: String
    /// The page's title, "" when it has none (`PageTitle`).
    var title: String
    var host: String
    var visitedAt: Date
    /// PNG/JPEG bytes for the site icon; nil until fetched.
    @Attribute(.externalStorage) var faviconData: Data?

    init(
        id: UUID = UUID(),
        urlString: String,
        title: String,
        host: String,
        visitedAt: Date = .now,
        faviconData: Data? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.host = host
        self.visitedAt = visitedAt
        self.faviconData = faviconData
    }

    var url: URL? { URL(string: urlString) }

    /// What names it in its row and a suggestion: `PageTitle.lineOne`.
    var lineOne: String { PageTitle.lineOne(title: title, source: host, address: urlString) }
}

extension LibraryStore {
    /// A web page finished loading: History lists it first, once per page (its canonical URL,
    /// `ArticleIdentity`), with its title, if it has one, and its icon; the oldest visits past
    /// `maxEntries` go. Stored with `commit`, as every other library change, so the audio work and
    /// listening progress waiting in the context are stored with it, and a failed save is logged.
    func recordVisit(url: URL, title: String?, faviconData: Data?) {
        guard url.isWeb else { return }
        let key = ArticleIdentity.canonicalURLString(from: url)
        let host = url.host ?? key
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var same = FetchDescriptor<RecentVisit>(predicate: #Predicate { $0.urlString == key })
        same.fetchLimit = 1
        if let hit = try? context.fetch(same).first {
            hit.title = trimmed
            hit.host = host
            hit.visitedAt = now()
            if let faviconData, !faviconData.isEmpty { hit.faviconData = faviconData }
        } else {
            // Room for it: the visits from the list's last place on go. Only those are read, before
            // the insert, so the new visit isn't among them.
            var stale = FetchDescriptor<RecentVisit>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
            stale.fetchOffset = RecentVisit.maxEntries - 1
            for visit in (try? context.fetch(stale)) ?? [] { context.delete(visit) }
            context.insert(RecentVisit(urlString: key, title: trimmed, host: host, visitedAt: now(),
                                       faviconData: faviconData))
        }
        commit("visit")
    }

    /// History's *Remove from History*: the visit goes from History (and the address field's
    /// suggestions); nothing else about the page changes.
    func removeVisit(_ visit: RecentVisit) {
        context.delete(visit)
        commit("remove visit")
    }
}
