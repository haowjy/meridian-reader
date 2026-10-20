import Foundation
import SwiftData

/// Where a save files the page.
enum SavePlacement: Equatable {
    /// An ordinary save (🔖, ⋯ → Save): a page the library has keeps its folder; a new one goes
    /// in no folder.
    case keep
    /// Picked in the Move tree: into this folder, or into no folder (nil, *Library (no folder)*),
    /// out of the folder it was in.
    case folder(Folder?)

    /// Where a new page goes.
    var folder: Folder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

/// Pages: opening, playing, saving, removing and deleting. One page per canonical URL: every
/// call finds the existing page for an address before it makes one.
extension LibraryStore {
    // MARK: - Opening

    /// A fresh extraction resolved to its page: the existing page's key, position and icon, or
    /// the address-derived key for a page the library doesn't have. A page holding text (saved,
    /// played, or a link carrying a text cache) is refreshed when the listen text changed; a link
    /// page stays a link.
    func readerArticle(url: URL, extracted: ExtractedArticle, document: ParagraphDocument? = nil) -> ReaderArticle {
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let existing = article(canonicalURL: canonical)
        let key = existing?.key ?? ArticleIdentity.articleKey(canonicalURL: canonical)
        var readerArticle = ReaderArticle(id: key, url: url, extracted: extracted, document: document)
        let freshFP = ArticleIdentity.contentFingerprint(paragraphs: readerArticle.document.paragraphs)
        guard let existing else {
            log("open \(canonical) key=\(Self.short(key)) new fp=\(freshFP.prefix(8))")
            return readerArticle
        }
        if existing.key == nil { existing.key = key }
        let stored = existing.cachedListenParagraphs
        readerArticle.trustedParagraphs = stored
        readerArticle.resumeParagraph = existing.positionParagraph
        readerArticle.artwork = existing.artworkData
        let storedFP = stored.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
        if existing.hasText, storedFP != freshFP {
            fill(existing, from: readerArticle)
            commit("refresh on open")
        }
        log("open \(canonical) key=\(Self.short(key)) \(existing.contentStateRaw) fp=\(freshFP.prefix(8)) stored=\(storedFP?.prefix(8) ?? "nil")")
        return readerArticle
    }

    // MARK: - Playing

    /// A listen to `readerArticle` started (🎧, the Reader's Listen): the page is dated (`lastPlayedAt`)
    /// and unfinished, and a page in a folder becomes its folder's place. The first play of a page
    /// the library doesn't have keeps it as a page not in the Library (`addedAt == nil`), so it
    /// survives a relaunch for 7 days; a link page in the Library keeps the text as a cache. A
    /// page removed from the Library is played without saving again: Recent lists it
    /// (`removedAt` cleared), as for any page you listen to. This and the writes below are kept
    /// until a save stores them (`PendingListening`): a rollback doesn't lose them.
    @discardableResult
    func recordPlayback(_ readerArticle: ReaderArticle) -> Article {
        let at = now()
        let (article, textNotStored) = playbackArticle(for: readerArticle)
        noteListening(article) {
            if textNotStored { $0.article = readerArticle }
            $0.start(at: at)
            $0.listened = true
        }
        applyStart(article, at: at)
        article.removedAt = nil
        commit("record playback")
        trimChapterAudio(behind: article)
        return article
    }

    /// The page `readerArticle` plays: the library's (its text refreshed when it changed), or a new
    /// page not in the Library. `textNotStored`: the store may not hold the text `readerArticle` has,
    /// because the page is new, its text was refreshed now, or it holds changes not stored yet
    /// (a refresh on open whose save failed, say).
    func playbackArticle(for readerArticle: ReaderArticle) -> (article: Article, textNotStored: Bool) {
        let article: Article
        var textNotStored = true
        if let existing = self.article(key: readerArticle.id, canonicalURL: readerArticle.origin.canonicalURL) {
            article = existing
            textNotStored = existing.hasChanges
            let storedFP = article.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !readerArticle.document.isEmpty,
               storedFP != ArticleIdentity.contentFingerprint(paragraphs: readerArticle.document.paragraphs) {
                fill(article, from: readerArticle)
                textNotStored = true
            }
            // Out of the Library, a page holding a play's text is a played page, never a link (a
            // link removed before it held text gets it here), so Recent can list it.
            if !article.isInLibrary, article.hasText { article.contentState = .saved }
        } else {
            article = Article(key: readerArticle.id, title: readerArticle.title, byline: readerArticle.sourceLabel,
                        urlString: readerArticle.origin.urlString, contentState: .saved, addedAt: nil,
                        artworkData: readerArticle.artwork)
            context.insert(article)
            fill(article, from: readerArticle)
            article.positionParagraph = readerArticle.resumeParagraph
            log("played, not saved: \(readerArticle.origin.canonicalURL ?? "-") key=\(Self.short(readerArticle.id))")
        }
        if article.artworkData == nil { article.artworkData = readerArticle.artwork }
        return (article, textNotStored)
    }

    /// A page the library has started playing again (a row's ▶, a book's Continue, a resume, a
    /// replay, the next chapter): dated and unfinished, and a page in a folder becomes its
    /// folder's place.
    /// It plays the text the page holds now. When the page holds changes not stored yet (a
    /// refresh on open whose save failed, say), the store may not hold that text: it is kept
    /// with the progress (`ReaderArticle(article:)`), as `recordPlayback` keeps its article, so a
    /// rollback puts the text back with the position on it. A page with nothing unsaved keeps
    /// no copy.
    func recordPlaybackStarted(_ article: Article) {
        let at = now()
        let textNotStored = article.hasChanges
        noteListening(article) {
            if textNotStored { $0.article = ReaderArticle(article: article) }
            $0.start(at: at)
        }
        applyStart(article, at: at)
        commit("playback started")
        trimChapterAudio(behind: article)
    }

    /// The listening position, written as it moves.
    func recordPosition(_ article: Article, paragraph: Int, utf16Offset: Int) {
        guard article.positionParagraph != paragraph || article.positionUTF16 != utf16Offset else { return }
        noteListening(article) { $0.position = PendingListening.Position(paragraph: paragraph, utf16Offset: utf16Offset) }
        applyPosition(article, paragraph: paragraph, utf16Offset: utf16Offset)
        commit("position")
    }

    /// Played to the end. The last playable page of a folder finishes the folder.
    func recordFinished(_ article: Article) {
        let at = now()
        noteListening(article) { $0.finishedAt = at }
        applyFinish(article, at: at)
        commit("finished")
    }

    /// A page became the place of its book or series: finished pages more than 2 behind it lose
    /// their audio (D7).
    private func trimChapterAudio(behind article: Article) {
        guard let folder = article.folder, folder.kind.isBookOrSeries else { return }
        trimFinishedAudio(folder: folder)
    }

    // MARK: - Saving

    /// Idempotent: the page for this address (or key) becomes saved in place, filed by
    /// `placement` (an ordinary save keeps its folder); otherwise a new saved page whose key is
    /// the reader key. Once that is stored, its audio is marked saved (`plan(.saved, key:)`: a launch that dies right after the save
    /// has it done by the next one). Never touches playback. A save that fails is rolled
    /// back and throws `LibraryStoreError.saveFailed`: no page is made, an existing one keeps its
    /// state and folder, and its audio is left alone.
    @discardableResult
    func save(_ readerArticle: ReaderArticle, placement: SavePlacement = .keep, playhead: Int? = nil) throws -> Article {
        try edit("save") { stageSave(readerArticle, placement: placement, playhead: playhead) }
    }

    private func stageSave(_ readerArticle: ReaderArticle, placement: SavePlacement, playhead: Int?) -> Article {
        let destination = placement.folder
        let article: Article
        if let existing = self.article(key: readerArticle.id, canonicalURL: readerArticle.origin.canonicalURL) {
            article = existing
            let storedFP = article.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !article.hasText || storedFP != ArticleIdentity.contentFingerprint(paragraphs: readerArticle.document.paragraphs) {
                fill(article, from: readerArticle)
            }
            if article.artworkData == nil { article.artworkData = readerArticle.artwork }
            if article.addedAt == nil {
                article.sortKey = nextSortKey(in: destination ?? article.folder)
            }
            log("save → existing \(Self.short(article.key)) (\(article.contentStateRaw), \(article.isInLibrary ? "in" : "not in") Library)")
        } else {
            article = Article(key: readerArticle.id, title: readerArticle.title, byline: readerArticle.sourceLabel,
                        urlString: readerArticle.origin.urlString, contentState: .saved, addedAt: nil,
                        sortKey: nextSortKey(in: destination), artworkData: readerArticle.artwork)
            context.insert(article)
            fill(article, from: readerArticle)
            article.positionParagraph = playhead ?? readerArticle.resumeParagraph
            log("save new \(readerArticle.origin.canonicalURL ?? "-") key=\(Self.short(readerArticle.id))")
        }
        article.contentState = .saved
        if article.addedAt == nil { article.addedAt = now() }
        if case .folder(let folder) = placement, article.folder !== folder {
            article.sortKey = nextSortKey(in: folder)
            movePlaceOff(article)
            article.setFolder(folder)
        }
        if let playhead { article.positionParagraph = playhead }
        if let key = article.key { plan(.saved, key: key) }
        return article
    }

    // MARK: - Removing and deleting

    /// *Remove from Library*, whichever path asks (a row's menu and swipe, *Remove from Recent*, Edit's *Remove*, 🔖 and
    /// the ⋯ of the browser, the Reader and Now Playing), all of `articles` in one save: each leaves
    /// its folder and every Library list it was in (`addedAt = nil`, `removedAt` now), Recent
    /// included (`LibraryQueries`), and once that is saved its audio turns ephemeral
    /// (`plan(.ephemeral, key:)`). The star stays, and with it the page's place in Favorites. A
    /// save puts it back in the Library. Nothing is deleted here: the launch prune deletes a
    /// removed page that isn't starred 7 days after its last play (one never played, at the next
    /// launch). A link
    /// holding the text of a play keeps it as a played page's; a link without text stays a link.
    /// A chapter leaves its book as any page leaves its folder. Once the remove is saved, the page
    /// you hear among them stops (`stopPlaybackIfPlaying`), as a deleted one does, and so does a
    /// session a waiting merge would move onto one (`keysWaitingToMerge`, read before the save,
    /// whose audio work can run that merge): out of every list, it would play on looking as if it
    /// had never gone. A save that fails is rolled back and throws `LibraryStoreError.saveFailed`:
    /// every page stays where it was, none removed, and playback goes on.
    func remove(_ articles: [Article]) throws {
        guard !articles.isEmpty else { return }
        let keys = articles.compactMap(\.key)
        let playing = keys + keysWaitingToMerge(into: Set(keys))
        try edit("remove") {
            for article in articles {
                if article.hasText { article.contentState = .saved }
                article.addedAt = nil
                article.removedAt = now()
                movePlaceOff(article)
                article.setFolder(nil)
                if let key = article.key { plan(.ephemeral, key: key) }
            }
        }
        log("remove: \(articles.map { Self.short($0.key) }.joined(separator: ", ")) → not in Library")
        for key in playing { stopPlaybackIfPlaying(key) }
    }

    /// Deletes the page, then its audio once that is saved. Playback of it stops first (its audio
    /// is being read), and so does a session a waiting merge would move onto it
    /// (`keysWaitingToMerge`); a folder's place on it moves to the page before. A save that
    /// fails is rolled back: the page and its audio stay.
    func delete(_ article: Article) {
        _ = try? edit("delete page") { deleteWithoutSaving(article) }
    }

    /// `delete` without the save, for deletes batched into one edit's save. The audio goes
    /// through the audio journal (`plan(.delete, key:)`), after that save. Stopping the page's playback
    /// records its position, which waits for that save too (`edit`).
    func deleteWithoutSaving(_ article: Article) {
        if let key = article.key {
            for playing in [key] + keysWaitingToMerge(into: [key]) { stopPlaybackIfPlaying(playing) }
            plan(.delete, key: key)
        }
        movePlaceOff(article)
        log("delete \(Self.short(article.key))")
        context.delete(article)
    }

    /// *Remove Downloads*: the page's audio only; the page stays saved.
    func deleteDownloads(_ article: Article) {
        guard let key = article.key else { return }
        try? audio.clearListenAudio(for: key)
    }

    // MARK: - Pieces

    /// A folder's place (`currentArticleKey`) on `article`, which leaves it or goes, moves to the page
    /// before it (none if it was the first).
    func movePlaceOff(_ article: Article) {
        guard let folder = article.folder, let key = article.key, folder.currentArticleKey == key else { return }
        let order = articles(in: folder)
        let index = order.firstIndex { $0 === article } ?? 0
        folder.currentArticleKey = index > 0 ? order[index - 1].key : nil
    }

    /// The page's text, listen blocks and metadata from `readerArticle`; the position is clamped to
    /// the new paragraph count. A web article writes its address. An article with none (a book
    /// chapter's, `ArticleOrigin.book`, as `ReaderArticle(article:)` makes it from a page with no
    /// address) leaves the page's alone: a copy made from a page writes back the page's own
    /// values, and an address-less page stays address-less.
    func fill(_ article: Article, from readerArticle: ReaderArticle) {
        if let url = readerArticle.origin.url {
            article.urlString = url.absoluteString
            article.canonicalURL = readerArticle.origin.canonicalURL
        }
        article.givenTitle = readerArticle.title
        article.byline = readerArticle.sourceLabel
        let paragraphs = readerArticle.document.isEmpty
            ? Article.buildListenDocument(plainText: readerArticle.plainText, cleanedHTML: readerArticle.cleanedHTML,
                                       title: readerArticle.title).paragraphs
            : readerArticle.document.paragraphs
        article.setText(html: readerArticle.cleanedHTML, plain: readerArticle.plainText, excerpt: readerArticle.excerpt, paragraphs: paragraphs)
        article.positionParagraph = min(article.positionParagraph, max(0, paragraphs.count - 1))
    }

    /// Drops a link's text cache and its position.
    func clearText(_ article: Article) {
        article.bodyHTML = nil
        article.plainTextData = nil
        article.listenBlocksData = nil
        article.listenBlocksVersion = 0
        article.paragraphCount = 0
        article.positionParagraph = 0
        article.positionUTF16 = 0
    }

    /// A sort key after everything already in `folder` (or among the pages in no folder).
    func nextSortKey(in folder: Folder?) -> Double {
        var descriptor: FetchDescriptor<Article>
        if let folder {
            descriptor = LibraryQueries.articles(inFolder: folder.id)
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate<Article> { $0.folderID == nil })
        }
        descriptor.sortBy = [SortDescriptor(\Article.sortKey, order: .reverse)]
        descriptor.fetchLimit = 1
        let last = (try? context.fetch(descriptor).first?.sortKey) ?? -1
        return last + 1
    }
}
