import Foundation
import SwiftData

/// Bounded Browse history entry (not a tab, not a Saved article).
@Model
final class RecentVisit {
    static let maxEntries = 30

    @Attribute(.unique) var id: UUID
    /// Canonical URL used for dedupe (no fragment).
    var urlString: String
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
}

enum RecentVisitRecorder {
    /// Normalize for dedupe: drop fragment, trim trailing slash on path-only "/".
    static func canonicalURLString(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        comps.fragment = nil
        // Drop default ports
        if comps.port == 80 || comps.port == 443 { comps.port = nil }
        guard let result = comps.url?.absoluteString else { return nil }
        if result.hasSuffix("/"), comps.path == "/" || comps.path.isEmpty {
            return String(result.dropLast())
        }
        return result
    }

    @MainActor
    static func record(
        url: URL,
        title: String?,
        faviconData: Data?,
        in context: ModelContext
    ) {
        guard let key = canonicalURLString(from: url) else { return }
        let host = url.host ?? key
        let displayTitle: String = {
            let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? host : trimmed
        }()

        let existing = try? context.fetch(
            FetchDescriptor<RecentVisit>(predicate: #Predicate { $0.urlString == key })
        )
        if let hit = existing?.first {
            hit.title = displayTitle
            hit.host = host
            hit.visitedAt = .now
            if let faviconData, !faviconData.isEmpty {
                hit.faviconData = faviconData
            }
        } else {
            context.insert(
                RecentVisit(
                    urlString: key,
                    title: displayTitle,
                    host: host,
                    faviconData: faviconData
                )
            )
        }

        // Cap list to last N by visitedAt.
        let all = (try? context.fetch(
            FetchDescriptor<RecentVisit>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        )) ?? []
        if all.count > RecentVisit.maxEntries {
            for stale in all[RecentVisit.maxEntries...] {
                context.delete(stale)
            }
        }
        try? context.save()
    }
}
