import Foundation

/// A site bookmark as `bookmarks.json` stores it (URL, title, icon). **Frozen:** the library
/// migration copied the file into Favorites (link pages) and nothing writes it again, so a
/// rollback to an older build finds its bookmarks as it left them.
struct SiteBookmark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var urlString: String
    var title: String
    var host: String
    var faviconData: Data?
    var createdAt: Date = .now
}

/// The frozen bookmarks file (`Application Support/Bookmarks/bookmarks.json`), read only by the
/// library migration.
enum LegacyBookmarks {
    /// The bookmarks in the user's order; none when the file is missing or empty. Throws when
    /// the file holds bytes that don't decode (the caller leaves them as they are).
    static func load(from url: URL) throws -> [SiteBookmark] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SiteBookmark].self, from: data)
    }
}
