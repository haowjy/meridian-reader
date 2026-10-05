import Foundation
import SwiftData

/// Which legacy rows and bookmarks the migration already copied (`library-migration.json`). The
/// copy skips anything in it, so a page deleted after the copy never comes back from its frozen
/// row, and rows made by an older build during a rollback (new ids) are copied next launch.
struct LibraryMigrationLedger: Codable, Equatable {
    var savedArticleIDs: Set<UUID> = []
    var bookmarkIDs: Set<UUID> = []

    static func load(from url: URL) -> LibraryMigrationLedger {
        guard let data = try? Data(contentsOf: url) else { return LibraryMigrationLedger() }
        return (try? JSONDecoder().decode(LibraryMigrationLedger.self, from: data)) ?? LibraryMigrationLedger()
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// The copy from the pre-library data into `Folder` / `Page`. Copy-once and non-destructive:
/// `SavedArticle` rows, `bookmarks.json`, the listen history and the audio cache are read, never
/// written. A page's key is its row's id, verbatim, so its audio, crash resume and pending bakes
/// stay where they are.
extension LibraryStore {
    struct MigrationReport: Equatable {
        var copiedArticles = 0
        var copiedBookmarks = 0
        /// Bookmarks whose page was already saved: that page moved into Favorites (D6).
        var savedIntoFavorites = 0
        var mergedDuplicates = 0
        var ledgerWritten = false
    }

    /// Copies every `SavedArticle` row and bookmark not yet in the ledger, folds in the listen
    /// history, runs dedupe, saves once, and only then records the copy in the ledger (a failed
    /// or interrupted save copies again next launch rather than losing anything).
    @discardableResult
    func migrateLegacy() -> MigrationReport {
        var report = MigrationReport()
        var ledger = LibraryMigrationLedger.load(from: legacy.ledgerURL)
        let rows = ((try? context.fetch(FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.savedAt)]))) ?? [])
            .filter { !ledger.savedArticleIDs.contains($0.id) }
        let bookmarks = LegacyBookmarks.load(from: legacy.bookmarksURL).filter { !ledger.bookmarkIDs.contains($0.id) }
        let favorites = favorites()
        guard !rows.isEmpty || !bookmarks.isEmpty else {
            commit("ensure favorites")
            return report
        }

        // Saved articles → saved pages in no folder, in the order they were saved.
        let history = ListenHistory(defaults: legacy.defaults)
        var copiedByURL: [String: Page] = [:]
        var looseKey = nextSortKey(in: nil)
        for row in rows {
            let page = copy(row, history: history, sortKey: looseKey)
            looseKey += 1
            if let url = page.canonicalURL { copiedByURL[url] = copiedByURL[url] ?? page }
            report.copiedArticles += 1
        }

        // Bookmarks → link pages in Favorites, in file order. A bookmark for a page that exists
        // (saved) files that page in Favorites at the bookmark's place (D6).
        var favoriteKey = nextSortKey(in: favorites)
        for bookmark in bookmarks {
            let canonical = ArticleIdentity.canonicalURLString(from: bookmark.urlString)
            if let existing = copiedByURL[canonical] ?? page(canonicalURL: canonical) {
                if !existing.isInFixedFolder {
                    if existing.addedAt == nil {
                        existing.contentState = .link
                        existing.addedAt = bookmark.createdAt
                    }
                    existing.setFolder(favorites)
                    existing.sortKey = favoriteKey
                    if existing.artworkData == nil { existing.artworkData = bookmark.faviconData }
                    report.savedIntoFavorites += 1
                }
            } else {
                let page = Page(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: bookmark.title,
                                byline: bookmark.host, urlString: bookmark.urlString, contentState: .link,
                                addedAt: bookmark.createdAt, sortKey: favoriteKey, artworkData: bookmark.faviconData)
                page.canonicalURL = canonical
                context.insert(page)
                page.setFolder(favorites)
                copiedByURL[canonical] = page
            }
            favoriteKey += 1
            report.copiedBookmarks += 1
        }

        report.mergedDuplicates = dedupe(saving: false).mergedPages
        guard commit("migration copy") else {
            context.rollback()
            log("migration: save failed, nothing recorded; copies again next launch")
            return report
        }
        ledger.savedArticleIDs.formUnion(rows.map(\.id))
        ledger.bookmarkIDs.formUnion(bookmarks.map(\.id))
        do {
            try ledger.write(to: legacy.ledgerURL)
            report.ledgerWritten = true
        } catch {
            log("migration: ledger write failed: \(error)")
        }
        log("migration: \(report)")
        ListenTimingLog.log("library_migration", [
            "articles": report.copiedArticles, "bookmarks": report.copiedBookmarks,
            "saved_into_favorites": report.savedIntoFavorites, "merged": report.mergedDuplicates,
            "ledger": report.ledgerWritten,
        ])
        return report
    }

    /// A saved page from a legacy row: the same key, text, listen blocks, position and icon,
    /// with its listen history as `lastPlayedAt` / `finishedAt`.
    private func copy(_ row: SavedArticle, history: ListenHistory, sortKey: Double) -> Page {
        let page = Page(key: row.id, title: row.title, byline: row.siteDomain, urlString: row.urlString,
                        contentState: .saved, addedAt: row.savedAt, sortKey: sortKey, artworkData: row.faviconData)
        page.cleanedHTML = row.cleanedHTML
        page.plainText = row.plainText
        page.excerpt = row.excerpt
        page.wordCount = row.wordCount
        page.listenBlocksData = row.listenBlocksData
        page.listenBlocksVersion = row.listenBlocksVersion
        page.detectedLanguageCode = row.detectedLanguageCode
        page.paragraphCount = Page.decodeAnyListenParagraphs(row.listenBlocksData)?.count ?? 0
        page.positionParagraph = row.playbackParagraphIndex
        page.positionUTF16 = row.playbackUTF16Offset
        if let entry = history.entry(for: row.id) {
            let at = Date(timeIntervalSince1970: entry.at)
            page.lastPlayedAt = at
            page.finishedAt = entry.done ? at : nil
        }
        context.insert(page)
        return page
    }
}

#if DEBUG
extension LibraryStore {
    /// `-rerunLibraryMigration`: deletes every folder and page and the ledger, so the next
    /// `migrateLegacy` copies everything again. Audio is left alone (pages keep their keys).
    func resetForMigrationRerun() {
        for page in (try? context.fetch(FetchDescriptor<Page>())) ?? [] { context.delete(page) }
        for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] { context.delete(folder) }
        commit("reset for migration rerun")
        try? FileManager.default.removeItem(at: legacy.ledgerURL)
        log("reset: library emptied, ledger deleted")
    }
}
#endif
