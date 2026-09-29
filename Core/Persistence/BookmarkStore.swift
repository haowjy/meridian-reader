import Foundation
import Observation

/// A plain website bookmark (e.g. a Royal Road story page): URL, title, icon. No article text or
/// audio is kept; that's what Saved articles are for.
struct SiteBookmark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var urlString: String
    var title: String
    var host: String
    var faviconData: Data?
    var createdAt: Date = .now

    var url: URL? { URL(string: urlString) }
}

/// Site bookmarks, kept in their own small JSON file (Application Support/Bookmarks), separate
/// from the SwiftData saved-article store. Order is the user's order (new ones go last, like
/// Safari Favorites).
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore(fileURL: BookmarkStore.defaultFileURL)

    private(set) var bookmarks: [SiteBookmark] = []
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SiteBookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bookmarks", isDirectory: true)
            .appendingPathComponent("bookmarks.json")
    }

    /// Same page = same canonical URL (tracking params / fragment ignored), like saved articles.
    static func key(for url: URL) -> String {
        ArticleIdentity.canonicalURLString(from: url)
    }

    /// Web pages (plus the UI tests' offline `reader-test://` pages).
    static func isBookmarkable(_ url: URL) -> Bool {
        ["http", "https", "reader-test"].contains(url.scheme?.lowercased() ?? "")
    }

    func bookmark(for url: URL?) -> SiteBookmark? {
        guard let url, Self.isBookmarkable(url) else { return nil }
        let key = Self.key(for: url)
        return bookmarks.first { $0.url.map(Self.key(for:)) == key }
    }

    @discardableResult
    func add(url: URL, title: String?, faviconData: Data?) -> SiteBookmark {
        if let existing = bookmark(for: url) { return existing }
        let host = url.host ?? url.absoluteString
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bookmark = SiteBookmark(urlString: url.absoluteString, title: trimmed.isEmpty ? host : trimmed,
                                    host: host, faviconData: faviconData)
        bookmarks.append(bookmark)
        persist()
        return bookmark
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        for i in offsets.sorted(by: >) where bookmarks.indices.contains(i) { bookmarks.remove(at: i) }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { bookmarks[$0] }
        var rest = bookmarks.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        bookmarks = rest
        persist()
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[i].title = trimmed
        persist()
    }

    func setFavicon(_ data: Data, for id: UUID) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[i].faviconData = data
        persist()
    }

    func removeAll() {
        bookmarks = []
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(bookmarks).write(to: fileURL, options: .atomic)
        } catch {
            ListenTimingLog.log("bookmarks_write_failed", ["error": "\(error)"])
        }
    }
}
