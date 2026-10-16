import Foundation
import SwiftData

/// The copy from the pre-library data into `Folder` / `Page`. Copy-once and non-destructive:
/// `SavedArticle` rows, `bookmarks.json` and the listen history are read, never written. A page's
/// key is its row's id, verbatim, so its audio, crash resume and pending bakes stay where they
/// are. What was copied is recorded as `LibraryMigrationReceipt`s in the same save as the copy;
/// the audio work of the layout pass and dedupe runs only after that save (`LibraryAudioWork`).
extension LibraryStore {
    struct MigrationReport: Equatable {
        var copiedArticles = 0
        var copiedBookmarks = 0
        /// Bookmarks whose page was already saved: that page is starred where it is (D6).
        var savedIntoFavorites = 0
        var mergedDuplicates = 0
        /// `bookmarks.json` holds bytes that don't decode: none of it was copied or recorded, and
        /// the file is left as it is (a later launch copies it if it becomes readable).
        var bookmarksUnreadable = false
        /// The copy and its receipts were saved.
        var saved = false
    }

    /// Copies every `SavedArticle` row and bookmark without a receipt and folds in the listen
    /// history; moves pages on older listen blocks to today's layout, then merges duplicates, so
    /// positions and audio are compared on the same paragraphs; and saves the pages and their
    /// receipts in one save (a failed or interrupted save leaves neither, and the next launch
    /// copies again). Receipts that can't be read stop the copy: copying again then would bring
    /// back what was deleted.
    @discardableResult
    func migrateLegacy() -> MigrationReport {
        var report = MigrationReport()
        let receipts: [LibraryMigrationReceipt]
        do {
            receipts = try context.fetch(FetchDescriptor<LibraryMigrationReceipt>())
        } catch {
            log("migration: receipts unreadable, nothing copied: \(error)")
            ListenTimingLog.log("library_migration", ["error": "receipts unreadable: \(error)"])
            return report
        }
        let copied = Set(receipts.compactMap { r in r.legacyID.map { "\(r.sourceRaw)|\($0)" } })
        func isCopied(_ id: UUID, _ source: LegacySource) -> Bool { copied.contains("\(source.rawValue)|\(id)") }
        let rows = ((try? context.fetch(FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.savedAt)]))) ?? [])
            .filter { !isCopied($0.id, .savedArticle) }
        var bookmarks: [SiteBookmark] = []
        do {
            bookmarks = try LegacyBookmarks.load(from: legacy.bookmarksURL).filter { !isCopied($0.id, .bookmark) }
        } catch {
            report.bookmarksUnreadable = true
            log("migration: bookmarks.json unreadable, left as it is, nothing copied from it: \(error)")
            ListenTimingLog.log("library_migration", ["error": "bookmarks unreadable: \(error)"])
        }
        // Nothing to copy (every launch after the first): no folder, no save.
        guard !rows.isEmpty || !bookmarks.isEmpty else { return report }

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

        // Bookmarks → starred pages, in file order. A bookmark for a page that exists stars it
        // where it is (D6): one in a folder stays there; one out of the Library joins it as a
        // link, in no folder. Any other bookmark is a new starred link page in no folder.
        for bookmark in bookmarks {
            let canonical = ArticleIdentity.canonicalURLString(from: bookmark.urlString)
            if let existing = copiedByURL[canonical] ?? page(canonicalURL: canonical) {
                if existing.addedAt == nil {
                    existing.contentState = .link
                    existing.addedAt = bookmark.createdAt
                    existing.sortKey = looseKey
                    looseKey += 1
                }
                existing.isFavorite = true
                if existing.artworkData == nil { existing.artworkData = bookmark.faviconData }
                if existing.isSaved { report.savedIntoFavorites += 1 }
            } else {
                let page = Page(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: bookmark.title,
                                byline: bookmark.host, urlString: bookmark.urlString, contentState: .link,
                                addedAt: bookmark.createdAt, sortKey: looseKey, artworkData: bookmark.faviconData)
                page.canonicalURL = canonical
                page.isFavorite = true
                context.insert(page)
                looseKey += 1
                copiedByURL[canonical] = page
            }
            report.copiedBookmarks += 1
        }

        let copiedAt = now()
        for row in rows { context.insert(LibraryMigrationReceipt(legacyID: row.id, source: .savedArticle, copiedAt: copiedAt)) }
        for bookmark in bookmarks { context.insert(LibraryMigrationReceipt(legacyID: bookmark.id, source: .bookmark, copiedAt: copiedAt)) }

        migrateParagraphLayout(saving: false)
        report.mergedDuplicates = dedupe(saving: false).mergedPages
        guard commit("migration copy") else {
            rollBack()
            log("migration: save failed, nothing copied or recorded; copies again next launch")
            return report
        }
        report.saved = true
        log("migration: \(report)")
        ListenTimingLog.log("library_migration", [
            "articles": report.copiedArticles, "bookmarks": report.copiedBookmarks,
            "saved_into_favorites": report.savedIntoFavorites, "merged": report.mergedDuplicates,
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
    /// `-rerunLibraryMigration`: deletes every folder, page and receipt, so the next
    /// `migrateLegacy` copies everything again. Audio is left alone (pages keep their keys).
    func resetForMigrationRerun() {
        for page in (try? context.fetch(FetchDescriptor<Page>())) ?? [] { context.delete(page) }
        for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] { context.delete(folder) }
        for receipt in (try? context.fetch(FetchDescriptor<LibraryMigrationReceipt>())) ?? [] { context.delete(receipt) }
        commit("reset for migration rerun")
        log("reset: library and receipts emptied")
    }
}
#endif
