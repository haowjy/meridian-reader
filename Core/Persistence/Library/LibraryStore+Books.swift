import Foundation
import SwiftData

/// Imported books: one `Folder(kind: .book)` per book key, one saved page per chapter, in order.
/// Every page is written with its content: a book holds no link pages.
extension LibraryStore {
    /// The book folder for a book key, wherever it is.
    func book(key: UUID) -> Folder? {
        let identifier: String? = key.uuidString
        let book = FolderKind.book.rawValue
        return try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate {
            $0.sourceIdentifier == identifier && $0.kindRaw == book
        })).first
    }

    /// A new book folder at the end of `destination` (the top level if nil), with one page per
    /// chapter, saved in one go: nothing is kept if the save fails.
    @discardableResult
    func addBook(_ details: FolderDetails, chapters: [PageContent], in destination: Folder?) throws -> Folder {
        if let destination, destination.kind.isFixed { throw LibraryTreeError.fixedDestination }
        let folder = Folder(name: details.title, kind: .book, sortKey: nextFolderSortKey(in: destination), createdAt: now())
        apply(details, to: folder)
        context.insert(folder)
        folder.parent = destination
        for chapter in chapters { insertChapter(chapter, in: folder) }
        try commitBook("add book")
        log("book \(details.title): \(chapters.count) chapters in \(destination?.displayName ?? "the top level")")
        return folder
    }

    /// *Replace* (decision D13): the book's pages rebuilt inside the same folder, which keeps its
    /// place, its name and its listening. A chapter is carried over from the page it was:
    /// - the page with its key and the same listen text keeps everything: position, finished,
    ///   audio;
    /// - the page with its key and other text keeps its audio where paragraphs match (aligned by
    ///   text), and its position only if the paragraph it is in is still there, word for word; it
    ///   is no longer finished (a finished one starts again from its top), and playback of it
    ///   stops;
    /// - otherwise the page with the same listen text, under another key, hands over its
    ///   position and its audio (merged under the new key), and a session playing it follows.
    ///
    /// Pages no chapter comes from are deleted; their audio goes once the save succeeds (audio
    /// work, `planDelete`), so a save that fails leaves every page and its audio as they were.
    /// The book's place follows its chapter, or is cleared. When the chapters' text, order or
    /// skipping changed, the book stays finished only if its place is a finished chapter with
    /// nothing playable after it.
    func replaceBook(_ folder: Folder, with details: FolderDetails, chapters: [PageContent]) throws {
        let old = playOrder(of: folder)
        let place = folder.currentPageKey
        let plan = Self.replacement(of: old, with: chapters)
        // Playback of a chapter that goes or changes stops before anything changes: stopping
        // records its position, which saves, and that save must not carry half a replacement.
        for page in plan.dropped { if let key = page.key { stopPlaybackIfPlaying(key) } }
        for (index, page) in plan.byKey where !Self.reads(page, as: chapters[index]) {
            if let key = page.key { stopPlaybackIfPlaying(key) }
        }

        for page in plan.dropped { dropChapter(page) }
        apply(details, to: folder)
        var changed = false
        var newPlace: UUID?
        var pages: [Page] = []
        for (index, chapter) in chapters.enumerated() {
            if let page = plan.byKey[index] {
                if page.skipsInPlayback != chapter.ref.skipsInPlayback { changed = true }
                if updateChapter(page, to: chapter, in: folder) { changed = true }
                if page.key == place { newPlace = place }
                pages.append(page)
            } else if let from = plan.byText[index] {
                let page = insertChapter(chapter, in: folder)
                carryListening(from: from, to: page)
                if let fromKey = from.key {
                    planMerge(from: fromKey, into: chapter.ref.key, fromParagraphs: from.cachedListenParagraphs ?? [],
                              paragraphs: chapter.document.paragraphs)
                    if fromKey == place { newPlace = chapter.ref.key }
                }
                if from.skipsInPlayback != chapter.ref.skipsInPlayback { changed = true }
                context.delete(from)
                pages.append(page)
            } else {
                pages.append(insertChapter(chapter, in: folder))
            }
        }
        if old.map(\.key) != pages.map(\.key) { changed = true }
        folder.currentPageKey = newPlace
        if changed { settleFinished(folder, chapters: pages) }
        try commitBook("replace book")
        log("book \(folder.name) replaced: \(chapters.count) chapters, \(plan.byKey.count) by key, \(plan.byText.count) by text, \(plan.dropped.count) dropped")
    }

    /// Which page each new chapter comes from (decision D13).
    private struct Replacement {
        /// New chapter index → the page with its key.
        var byKey: [Int: Page] = [:]
        /// New chapter index → a page with its listen text under another key.
        var byText: [Int: Page] = [:]
        /// Pages no chapter comes from.
        var dropped: [Page] = []
    }

    private static func replacement(of old: [Page], with chapters: [PageContent]) -> Replacement {
        var plan = Replacement()
        var byKey: [UUID: Page] = [:]
        for page in old { if let key = page.key, byKey[key] == nil { byKey[key] = page } }
        var claimed = Set<ObjectIdentifier>()
        for (index, chapter) in chapters.enumerated() {
            if let page = byKey[chapter.ref.key], claimed.insert(ObjectIdentifier(page)).inserted {
                plan.byKey[index] = page
            }
        }
        var byText: [String: [Page]] = [:]
        for page in old where !claimed.contains(ObjectIdentifier(page)) {
            guard let paragraphs = page.cachedListenParagraphs else { continue }
            byText[ArticleIdentity.contentFingerprint(paragraphs: paragraphs), default: []].append(page)
        }
        for (index, chapter) in chapters.enumerated() where plan.byKey[index] == nil {
            let fingerprint = ArticleIdentity.contentFingerprint(paragraphs: chapter.document.paragraphs)
            if let page = byText[fingerprint]?.first {
                byText[fingerprint]?.removeFirst()
                plan.byText[index] = page
                claimed.insert(ObjectIdentifier(page))
            }
        }
        plan.dropped = old.filter { !claimed.contains(ObjectIdentifier($0)) }
        return plan
    }

    /// After *Replace* changed what the book's chapters say or their order: the book stays
    /// finished only while its place is a finished chapter with nothing playable after it, the
    /// rule it finished by (`noteChapterFinished`). *Replace* never finishes a book; listening
    /// does.
    private func settleFinished(_ folder: Folder, chapters: [Page]) {
        guard folder.finishedAt != nil else { return }
        let place = folder.currentPageKey.flatMap { key in chapters.first { $0.key == key } }
        if let place, place.finishedAt != nil,
           ChapterAdvance.after(place.listenKey, in: chapterSnapshot(of: folder, pages: chapters)) == .none {
            return
        }
        folder.finishedAt = nil
        log("book \(folder.name): no longer finished after replace")
    }

    // MARK: - Pieces

    private func apply(_ details: FolderDetails, to folder: Folder) {
        folder.byline = details.byline
        folder.coverData = details.cover
        folder.sourceURLString = details.sourceURL?.absoluteString
        folder.sourceIdentifier = details.sourceIdentifier
        folder.sourceStateData = details.sourceState
        folder.languageCode = details.languageCode
    }

    @discardableResult
    private func insertChapter(_ chapter: PageContent, in folder: Folder) -> Page {
        let page = Page(key: chapter.ref.key, title: chapter.title, byline: folder.byline ?? "", urlString: nil,
                        contentState: .saved, addedAt: now(), sortKey: Double(chapter.ref.ordinal))
        context.insert(page)
        fillChapter(page, from: chapter)
        page.setFolder(folder)
        return page
    }

    /// Whether `page` reads as `chapter` reads: the same listen paragraphs.
    private static func reads(_ page: Page, as chapter: PageContent) -> Bool {
        (page.cachedListenParagraphs ?? page.listenDocument().paragraphs) == chapter.document.paragraphs
    }

    /// A chapter's page keeps its listening when its text is unchanged; otherwise see
    /// `replaceBook`. Returns whether its text changed.
    private func updateChapter(_ page: Page, to chapter: PageContent, in folder: Folder) -> Bool {
        let old = page.cachedListenParagraphs ?? page.listenDocument().paragraphs
        let new = chapter.document
        page.byline = folder.byline ?? ""
        page.sortKey = Double(chapter.ref.ordinal)
        if old == new.paragraphs {
            fillChapter(page, from: chapter)
            return false
        }
        // What was heard isn't what it says now: a finished chapter starts again from its top,
        // so neither Continue nor the D7 trim treats the revision as heard.
        let wasFinished = page.finishedAt != nil
        page.finishedAt = nil
        let position = wasFinished ? nil : Self.carriedPosition(paragraph: page.positionParagraph,
                                                                 utf16Offset: page.positionUTF16, from: old, to: new)
        fillChapter(page, from: chapter)
        page.positionParagraph = position?.paragraph ?? 0
        page.positionUTF16 = position?.utf16Offset ?? 0
        if let key = page.key { planAlign(key: key, old: old, new: new.paragraphs) }
        return true
    }

    /// A chapter no new chapter comes from: the page goes in this save; its audio once the save
    /// succeeds (`planDelete`). Playback of it was stopped before.
    private func dropChapter(_ page: Page) {
        if let key = page.key { planDelete(key: key) }
        log("delete \(Self.short(page.key))")
        context.delete(page)
    }

    private func fillChapter(_ page: Page, from chapter: PageContent) {
        page.title = chapter.title
        page.locator = Self.locator(of: chapter.ref)
        page.cleanedHTML = chapter.bodyHTML
        page.plainText = chapter.plainText
        page.excerpt = chapter.excerpt
        page.wordCount = EPUBWordCount.count(chapter.plainText)
        page.skipsInPlayback = chapter.ref.skipsInPlayback
        page.storeListenParagraphs(chapter.document.paragraphs)
    }

    private func carryListening(from old: Page, to page: Page) {
        page.positionParagraph = old.positionParagraph
        page.positionUTF16 = old.positionUTF16
        page.lastPlayedAt = old.lastPlayedAt
        page.finishedAt = old.finishedAt
        page.addedAt = old.addedAt ?? page.addedAt
    }

    private func commitBook(_ what: String) throws {
        guard commit(what) else {
            rollBack()
            throw LibraryStoreError.saveFailed
        }
    }

    private static func locator(of ref: PageRef) -> String? {
        switch ref.locator {
        case .book(let locator): locator.pageLocator
        case .web: nil
        }
    }

    /// Where a position on `old` paragraphs lands on `new`: the same spot in the nearest paragraph
    /// with the same text, or nil when that paragraph is gone.
    static func carriedPosition(paragraph: Int, utf16Offset: Int, from old: [String],
                                to new: ParagraphDocument) -> (paragraph: Int, utf16Offset: Int)? {
        guard old.indices.contains(paragraph) else { return nil }
        let text = old[paragraph]
        guard let target = new.paragraphs.indices.filter({ new.paragraphs[$0] == text })
            .min(by: { abs($0 - paragraph) < abs($1 - paragraph) }) else { return nil }
        let oldRange = ParagraphDocument(parts: old).utf16Ranges[paragraph]
        let within = min(max(0, utf16Offset - oldRange.location), max(0, oldRange.length - 1))
        return (target, new.utf16Ranges[target].location + within)
    }
}

/// A library write that didn't happen.
enum LibraryStoreError: Error, Equatable {
    /// SwiftData refused the save; nothing changed.
    case saveFailed
}
