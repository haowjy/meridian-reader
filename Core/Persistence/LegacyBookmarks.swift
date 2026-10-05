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
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Bookmarks", directoryHint: .isDirectory)
            .appending(path: "bookmarks.json")
    }

    /// The bookmarks in the user's order; none when the file is missing or unreadable.
    static func load(from url: URL) -> [SiteBookmark] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SiteBookmark].self, from: data)) ?? []
    }
}
