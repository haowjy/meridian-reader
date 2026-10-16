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
        let existing = page(canonicalURL: canonical)
        let key = existing?.key ?? ArticleIdentity.articleKey(canonicalURL: canonical)
        var article = ReaderArticle(id: key, url: url, extracted: extracted, document: document)
        let freshFP = ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs)
        guard let existing else {
            log("open \(canonical) key=\(Self.short(key)) new fp=\(freshFP.prefix(8))")
            return article
        }
        if existing.key == nil { existing.key = key }
        let stored = existing.cachedListenParagraphs
        article.trustedParagraphs = stored
        article.resumeParagraph = existing.positionParagraph
        article.artwork = existing.artworkData
        let storedFP = stored.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
        if existing.hasText, storedFP != freshFP {
            fill(existing, from: article)
            commit("refresh on open")
        }
        log("open \(canonical) key=\(Self.short(key)) \(existing.contentStateRaw) fp=\(freshFP.prefix(8)) stored=\(storedFP?.prefix(8) ?? "nil")")
        return article
    }

    // MARK: - Playing

    /// A listen to `article` started (🎧, the Reader's Listen): the page is dated (`lastPlayedAt`)
    /// and unfinished, and a page in a folder becomes its folder's place. The first play of a page
    /// the library doesn't have keeps it as a page not in the Library (`addedAt == nil`), so it
    /// survives a relaunch for 7 days; a link page keeps the text as a cache. A page removed from
    /// the Library is played without saving again: "Not saved" lists it (`removedAt` cleared), as
    /// for any page you listen to. This and the writes below are kept until a save stores them
    /// (`PendingListening`): a rollback doesn't lose them.
    @discardableResult
    func recordPlayback(_ article: ReaderArticle) -> Page {
        let at = now()
        let (page, textNotStored) = playbackPage(for: article)
        noteListening(page) {
            if textNotStored { $0.article = article }
            $0.start(at: at)
            $0.listened = true
        }
        applyStart(page, at: at)
        page.removedAt = nil
        commit("record playback")
        trimChapterAudio(behind: page)
        return page
    }

    /// The page `article` plays: the library's (its text refreshed when it changed), or a new
    /// page not in the Library. `textNotStored`: the store may not hold the text `article` has,
    /// because the page is new, its text was refreshed now, or it holds changes not stored yet
    /// (a refresh on open whose save failed, say).
    func playbackPage(for article: ReaderArticle) -> (page: Page, textNotStored: Bool) {
        let page: Page
        var textNotStored = true
        if let existing = self.page(key: article.id, canonicalURL: article.origin.canonicalURL) {
            page = existing
            textNotStored = existing.hasChanges
            let storedFP = page.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !article.document.isEmpty,
               storedFP != ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) {
                fill(page, from: article)
                textNotStored = true
            }
        } else {
            page = Page(key: article.id, title: article.title, byline: article.sourceLabel,
                        urlString: article.origin.urlString, contentState: .saved, addedAt: nil,
                        artworkData: article.artwork)
            context.insert(page)
            fill(page, from: article)
            page.positionParagraph = article.resumeParagraph
            log("played, not saved: \(article.origin.canonicalURL ?? "-") key=\(Self.short(article.id))")
        }
        if page.artworkData == nil { page.artworkData = article.artwork }
        return (page, textNotStored)
    }

    /// A page the library has started playing again (a row's ▶, a book's Continue, a resume, a
    /// replay, the next chapter): dated and unfinished, and a page in a folder becomes its
    /// folder's place.
    /// It plays the text the page holds now. When the page holds changes not stored yet (a
    /// refresh on open whose save failed, say), the store may not hold that text: it is kept
    /// with the progress (`ReaderArticle(page:)`), as `recordPlayback` keeps its article, so a
    /// rollback puts the text back with the position on it. A page with nothing unsaved keeps
    /// no copy.
    func recordPlaybackStarted(_ page: Page) {
        let at = now()
        let textNotStored = page.hasChanges
        noteListening(page) {
            if textNotStored { $0.article = ReaderArticle(page: page) }
            $0.start(at: at)
        }
        applyStart(page, at: at)
        commit("playback started")
        trimChapterAudio(behind: page)
    }

    /// The listening position, written as it moves.
    func recordPosition(_ page: Page, paragraph: Int, utf16Offset: Int) {
        guard page.positionParagraph != paragraph || page.positionUTF16 != utf16Offset else { return }
        noteListening(page) { $0.position = PendingListening.Position(paragraph: paragraph, utf16Offset: utf16Offset) }
        applyPosition(page, paragraph: paragraph, utf16Offset: utf16Offset)
        commit("position")
    }

    /// Played to the end. The last playable page of a folder finishes the folder.
    func recordFinished(_ page: Page) {
        let at = now()
        noteListening(page) { $0.finishedAt = at }
        applyFinish(page, at: at)
        commit("finished")
    }

    /// A page became the place of its book or series: finished pages more than 2 behind it lose
    /// their audio (D7).
    private func trimChapterAudio(behind page: Page) {
        guard let folder = page.folder, folder.kind.isBookOrSeries else { return }
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
    func save(_ article: ReaderArticle, placement: SavePlacement = .keep, playhead: Int? = nil) throws -> Page {
        try edit("save") { stageSave(article, placement: placement, playhead: playhead) }
    }

    private func stageSave(_ article: ReaderArticle, placement: SavePlacement, playhead: Int?) -> Page {
        let destination = placement.folder
        let page: Page
        if let existing = self.page(key: article.id, canonicalURL: article.origin.canonicalURL) {
            page = existing
            let storedFP = page.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if !page.hasText || storedFP != ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) {
                fill(page, from: article)
            }
            if page.artworkData == nil { page.artworkData = article.artwork }
            if page.addedAt == nil {
                page.sortKey = nextSortKey(in: destination ?? page.folder)
            }
            log("save → existing \(Self.short(page.key)) (\(page.contentStateRaw), \(page.isInLibrary ? "in" : "not in") Library)")
        } else {
            page = Page(key: article.id, title: article.title, byline: article.sourceLabel,
                        urlString: article.origin.urlString, contentState: .saved, addedAt: nil,
                        sortKey: nextSortKey(in: destination), artworkData: article.artwork)
            context.insert(page)
            fill(page, from: article)
            page.positionParagraph = playhead ?? article.resumeParagraph
            log("save new \(article.origin.canonicalURL ?? "-") key=\(Self.short(article.id))")
        }
        page.contentState = .saved
        if page.addedAt == nil { page.addedAt = now() }
        if case .folder(let folder) = placement, page.folder !== folder {
            page.sortKey = nextSortKey(in: folder)
            movePlaceOff(page)
            page.setFolder(folder)
        }
        if let playhead { page.positionParagraph = playhead }
        if let key = page.key { plan(.saved, key: key) }
        return page
    }

    /// Unsave (🔖, ⋯ → Remove from Library) a page saved in the Library: a page in a folder stays
    /// there as a link (a favorite stays a favorite); a page in no folder, or one with no address
    /// to keep as a link (a book's chapter), is removed from the Library (`remove`: in no list
    /// after). The audio stays, back on the ephemeral TTL once that is saved (`plan(.ephemeral, key:)`), so
    /// playback goes on. Any other page has nothing to unsave. A save that fails is rolled back
    /// and throws `LibraryStoreError.saveFailed`: still saved.
    func unsave(_ page: Page) throws {
        guard page.isSavedToLibrary else { return }
        if (page.folder != nil || page.isFavorite), page.url != nil {
            try edit("unsave to link") {
                page.contentState = .link
                // A link's text is a cache of its last play; one never played has nothing to keep.
                if page.lastPlayedAt == nil { clearText(page) }
                if let key = page.key { plan(.ephemeral, key: key) }
            }
            log("unsave \(Self.short(page.key)) → link in \(page.folder?.name ?? "-")")
        } else {
            try remove([page])
        }
    }

    // MARK: - Removing and deleting

    /// *Remove from Library* (a row's menu and swipe, Edit's *Remove*, unsaving a page in no
    /// folder), all of `pages` in one save: a saved page leaves the Library and every list it was
    /// in (`addedAt = nil`, `removedAt` now, no folder, no longer a favorite), *Not saved*
    /// included (`LibraryQueries`), and is pruned 7 days after it was last played; once that is
    /// saved its audio turns ephemeral (`plan(.ephemeral, key:)`).
    /// A link page is deleted, unless it holds the text of a play, when it is kept as any removed
    /// page. A chapter leaves its book as any page leaves its folder. Never touches playback. A
    /// save that fails is rolled back and throws `LibraryStoreError.saveFailed`: every page stays
    /// where it was, none removed.
    func remove(_ pages: [Page]) throws {
        guard !pages.isEmpty else { return }
        var notes: [String] = []
        try edit("remove") {
            for page in pages {
                if page.isLink && !page.hasText {
                    notes.append("link \(Self.short(page.key)) deleted")
                    context.delete(page)
                    continue
                }
                page.contentState = .saved
                page.addedAt = nil
                page.removedAt = now()
                page.isFavorite = false
                movePlaceOff(page)
                page.setFolder(nil)
                if let key = page.key { plan(.ephemeral, key: key) }
                notes.append("\(Self.short(page.key)) → not in Library")
            }
        }
        log("remove: \(notes.joined(separator: ", "))")
    }

    /// Deletes the page, then its audio once that is saved. Playback of it stops first (its audio
    /// is being read), and so does a session a waiting merge would move onto it
    /// (`keysWaitingToMerge`); a folder's place on it moves to the page before. A save that
    /// fails is rolled back: the page and its audio stay.
    func delete(_ page: Page) {
        _ = try? edit("delete page") { deleteWithoutSaving(page) }
    }

    /// `delete` without the save, for deletes batched into one edit's save. The audio goes
    /// through the audio journal (`plan(.delete, key:)`), after that save. Stopping the page's playback
    /// records its position, which waits for that save too (`edit`).
    func deleteWithoutSaving(_ page: Page) {
        if let key = page.key {
            for playing in [key] + keysWaitingToMerge(into: [key]) { stopPlaybackIfPlaying(playing) }
            plan(.delete, key: key)
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

    /// A folder's place (`currentPageKey`) on `page`, which leaves it or goes, moves to the page
    /// before it (none if it was the first).
    func movePlaceOff(_ page: Page) {
        guard let folder = page.folder, let key = page.key, folder.currentPageKey == key else { return }
        let order = pages(in: folder)
        let index = order.firstIndex { $0 === page } ?? 0
        folder.currentPageKey = index > 0 ? order[index - 1].key : nil
    }

    /// The page's text, listen blocks and metadata from `article`; the position is clamped to
    /// the new paragraph count. A web article writes its address. An article with none (a book
    /// chapter's, `PageOrigin.book`, as `ReaderArticle(page:)` makes it from a page with no
    /// address) leaves the page's alone: a copy made from a page writes back the page's own
    /// values, and an address-less page stays address-less.
    func fill(_ page: Page, from article: ReaderArticle) {
        if let url = article.origin.url {
            page.urlString = url.absoluteString
            page.canonicalURL = article.origin.canonicalURL
        }
        page.title = article.title
        page.byline = article.sourceLabel
        let paragraphs = article.document.isEmpty
            ? Page.buildListenDocument(plainText: article.plainText, cleanedHTML: article.cleanedHTML,
                                       title: article.title).paragraphs
            : article.document.paragraphs
        page.setText(html: article.cleanedHTML, plain: article.plainText, excerpt: article.excerpt, paragraphs: paragraphs)
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
