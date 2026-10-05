import Foundation
import SwiftData

/// Pages: opening, playing, saving, removing and deleting. One page per canonical URL: every
/// call finds the existing page for an address before it makes one.
extension LibraryStore {
    // MARK: - Opening

    /// A fresh extraction resolved to its page: the existing page's key, position and icon, or
    /// the address-derived key for a page the library doesn't have. A page holding text (saved,
    /// played, or a link carrying a text cache) is refreshed when the listen text changed; a link
    /// page stays a link.
    func readerArticle(url: URL, extracted: ExtractedArticle) -> ReaderArticle {
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let existing = page(canonicalURL: canonical)
        let key = existing?.key ?? ArticleIdentity.articleKey(canonicalURL: canonical)
        var article = ReaderArticle(id: key, url: url, extracted: extracted)
        let freshFP = ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs)
        guard let existing else {
            log("open \(canonical) key=\(Self.short(key)) new fp=\(freshFP.prefix(8))")
            return article
        }
        if existing.key == nil { existing.key = key }
        let stored = existing.cachedListenParagraphs
        article.trustedParagraphs = stored
        article.resumeParagraph = existing.positionParagraph
        article.faviconData = existing.artworkData
        let storedFP = stored.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
        if existing.hasText, storedFP != freshFP {
            fill(existing, from: article)
            commit("refresh on open")
        }
        log("open \(canonical) key=\(Self.short(key)) \(existing.contentStateRaw) fp=\(freshFP.prefix(8)) stored=\(storedFP?.prefix(8) ?? "nil")")
        return article
    }

    // MARK: - Playing

    /// The page started playing: it is dated (`lastPlayedAt`) and unfinished. The first play of a
    /// page the library doesn't have keeps it as a page not in the Library (`addedAt == nil`), so
    /// it survives a relaunch for 7 days; a link page keeps the text as a cache.
    @discardableResult
    func recordPlayback(_ article: ReaderArticle) -> Page {
        let page: Page
        if let existing = self.page(key: article.id, canonicalURL: article.canonicalURL) {
            page = existing
            let storedFP = page.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !article.document.isEmpty,
               storedFP != ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) {
                fill(page, from: article)
            }
        } else {
            page = Page(key: article.id, title: article.title, byline: article.siteDomain,
                        urlString: article.urlString, contentState: .saved, addedAt: nil,
                        artworkData: article.faviconData)
            context.insert(page)
            fill(page, from: article)
            page.positionParagraph = article.resumeParagraph
            log("played, not saved: \(article.canonicalURL) key=\(Self.short(article.id))")
        }
        if page.artworkData == nil { page.artworkData = article.faviconData }
        page.lastPlayedAt = now()
        page.finishedAt = nil
        commit("record playback")
        return page
    }

    /// A saved page started playing (no article at hand): dated and unfinished.
    func recordPlaybackStarted(key: UUID) {
        guard let page = page(key: key) else { return }
        page.lastPlayedAt = now()
        page.finishedAt = nil
        commit("playback started")
    }

    /// The listening position, written as it moves.
    func recordPosition(key: UUID, paragraph: Int, utf16Offset: Int) {
        guard let page = page(key: key) else { return }
        guard page.positionParagraph != paragraph || page.positionUTF16 != utf16Offset else { return }
        page.positionParagraph = paragraph
        page.positionUTF16 = utf16Offset
        commit("position")
    }

    /// Played to the end.
    func recordFinished(key: UUID) {
        guard let page = page(key: key) else { return }
        page.finishedAt = now()
        page.lastPlayedAt = now()
        commit("finished")
    }

    // MARK: - Saving

    /// Idempotent: the page for this address (or key) becomes saved in place, keeping its folder
    /// unless `folder` is given; otherwise a new saved page whose key is the reader key. Its
    /// audio is marked saved. Never touches playback.
    @discardableResult
    func save(_ article: ReaderArticle, in folder: Folder? = nil, playhead: Int? = nil) -> Page {
        let page: Page
        if let existing = self.page(key: article.id, canonicalURL: article.canonicalURL) {
            page = existing
            let storedFP = page.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !page.hasText || storedFP != ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) {
                fill(page, from: article)
            }
            if page.artworkData == nil { page.artworkData = article.faviconData }
            if page.addedAt == nil {
                page.sortKey = nextSortKey(in: folder ?? page.folder)
            }
            log("save → existing \(Self.short(page.key)) (\(page.contentStateRaw), \(page.isInLibrary ? "in" : "not in") Library)")
        } else {
            page = Page(key: article.id, title: article.title, byline: article.siteDomain,
                        urlString: article.urlString, contentState: .saved, addedAt: nil,
                        sortKey: nextSortKey(in: folder), artworkData: article.faviconData)
            context.insert(page)
            fill(page, from: article)
            page.positionParagraph = playhead ?? article.resumeParagraph
            log("save new \(article.canonicalURL) key=\(Self.short(article.id))")
        }
        page.contentState = .saved
        if page.addedAt == nil { page.addedAt = now() }
        if let folder, !page.isInFixedFolder, page.folder !== folder, !folder.kind.isFixed {
            page.sortKey = nextSortKey(in: folder)
            page.setFolder(folder)
        }
        if let playhead { page.positionParagraph = playhead }
        commit("save")
        if let key = page.key { tts.migrateListenCache(from: key, to: key) }
        return page
    }

    /// Unsave (🔖, ⋯ → Remove from Saved): a page in a folder stays there as a link (a favorite
    /// stays a favorite); a page in no folder is removed from the Library. Pages in books and
    /// series aren't unsaved. The audio stays, back on the ephemeral TTL, so playback goes on.
    func unsave(_ page: Page) {
        guard page.isSaved, !page.isInFixedFolder else { return }
        if page.folder != nil {
            page.contentState = .link
            // A link's text is a cache of its last play; one never played has nothing to keep.
            if page.lastPlayedAt == nil { clearText(page) }
            commit("unsave to link")
            if let key = page.key { tts.markListenCacheEphemeral(key, canonicalURL: page.canonicalURL) }
            log("unsave \(Self.short(page.key)) → link in \(page.folder?.displayName ?? "-")")
        } else {
            remove(page)
        }
    }

    // MARK: - Links

    /// A link page for `url` in `folder`, or the existing page for that address (unchanged).
    @discardableResult
    func addLink(url: URL, title: String?, artwork: Data?, in folder: Folder?) -> Page {
        if let existing = page(url: url) { return existing }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let host = url.host ?? url.absoluteString
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let page = Page(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: trimmed.isEmpty ? host : trimmed,
                        byline: host, urlString: url.absoluteString, contentState: .link, addedAt: now(),
                        sortKey: nextSortKey(in: folder), artworkData: artwork)
        context.insert(page)
        page.setFolder(folder)
        commit("add link")
        return page
    }

    // MARK: - Removing and deleting

    /// *Remove from Library*: a saved page leaves the Library (`addedAt = nil`, no folder) and is
    /// pruned 7 days after it was last played; its audio turns ephemeral. A link page is deleted,
    /// unless it holds the text of a play, when it is kept like any played page. Not for pages in
    /// books and series. Never touches playback.
    func remove(_ page: Page) {
        guard !page.isInFixedFolder else { return }
        if page.isLink && !page.hasText {
            log("remove link \(Self.short(page.key))")
            context.delete(page)
            commit("remove link")
            return
        }
        page.contentState = .saved
        page.addedAt = nil
        page.setFolder(nil)
        commit("remove")
        if let key = page.key { tts.markListenCacheEphemeral(key, canonicalURL: page.canonicalURL) }
        log("remove \(Self.short(page.key)) → not in Library")
    }

    /// Deletes the page and its audio. Playback of it stops first (its audio is being read), and
    /// a book's place on it moves to the chapter before.
    func delete(_ page: Page) {
        deleteWithoutSaving(page)
        commit("delete page")
    }

    /// `delete` without the save, for deletes batched into one save.
    func deleteWithoutSaving(_ page: Page) {
        if let key = page.key {
            stopPlaybackIfPlaying(key)
            tts.handleArticleDeleted(key)
        }
        movePlaceOff(page)
        log("delete \(Self.short(page.key))")
        context.delete(page)
    }

    /// *Delete Downloads*: the page's audio only; the page stays saved.
    func deleteDownloads(_ page: Page) {
        guard let key = page.key else { return }
        try? tts.clearListenAudio(for: key)
    }

    // MARK: - Pieces

    /// A book's or series' place (`currentPageKey`) on `page` moves to the chapter before it
    /// (none if it was the first).
    func movePlaceOff(_ page: Page) {
        guard let folder = page.folder, let key = page.key, folder.currentPageKey == key else { return }
        let order = playOrder(of: folder)
        let index = order.firstIndex { $0 === page } ?? 0
        folder.currentPageKey = index > 0 ? order[index - 1].key : nil
    }

    /// The page's text, listen blocks and metadata from `article`; the position is clamped to
    /// the new paragraph count.
    func fill(_ page: Page, from article: ReaderArticle) {
        page.urlString = article.urlString
        page.canonicalURL = article.canonicalURL
        page.title = article.title
        page.byline = article.siteDomain
        page.cleanedHTML = article.cleanedHTML
        page.plainText = article.plainText
        page.excerpt = article.excerpt
        page.wordCount = SavedArticle.wordCount(of: article.plainText)
        let paragraphs = article.document.isEmpty
            ? Page.buildListenDocument(plainText: article.plainText, cleanedHTML: article.cleanedHTML,
                                       title: article.title).paragraphs
            : article.document.paragraphs
        page.storeListenParagraphs(paragraphs)
        page.positionParagraph = min(page.positionParagraph, max(0, paragraphs.count - 1))
    }

    /// Drops a link's text cache and its position.
    func clearText(_ page: Page) {
        page.bodyHTML = nil
        page.plainTextData = nil
        page.listenBlocksData = nil
        page.listenBlocksVersion = 0
        page.paragraphCount = 0
        page.positionParagraph = 0
        page.positionUTF16 = 0
    }

    /// A sort key after everything already in `folder` (or among the pages in no folder).
    func nextSortKey(in folder: Folder?) -> Double {
        var descriptor: FetchDescriptor<Page>
        if let folder {
            descriptor = LibraryQueries.pages(inFolder: folder.id)
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate<Page> { $0.folderID == nil })
        }
        descriptor.sortBy = [SortDescriptor(\Page.sortKey, order: .reverse)]
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor).first?.sortKey) ?? -1
        return last + 1
    }
}
