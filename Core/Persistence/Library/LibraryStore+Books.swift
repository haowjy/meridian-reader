import Foundation
import SwiftData

/// Imported books: one `Folder(kind: .book)` per book key, one saved page per chapter. A book is a
/// folder like any other (decision D19): its chapters start in the book's order, and can be
/// reordered, moved out and joined by other pages. Its record of its chapters
/// (`BookSourceState.chapterKeys`) is how *Replace* finds them wherever they are now. Every
/// chapter is written with its content: a book holds no link pages of its own.
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
    /// chapter in the book's order, in one edit (`edit`): a save that fails is rolled back and
    /// throws `LibraryStoreError.saveFailed`, and nothing is kept. A chapter the library already
    /// has under its key (moved out of a copy of the book deleted since) is brought up to date
    /// where it is, not made twice; one no longer in the Library comes back into the book.
    @discardableResult
    func addBook(_ details: FolderDetails, chapters: [PageContent], in destination: Folder?) throws -> Folder {
        let plan = replacement(of: [], in: nil, with: chapters)
        stopPlayback(changedBy: plan, chapters: chapters)
        let folder = try edit("add book") {
            let folder = Folder(name: details.title, kind: .book, sortKey: nextFolderSortKey(in: destination), createdAt: now())
            context.insert(folder)
            folder.parent = destination
            apply(details, chapters: chapters, to: folder)
            stageChapters(chapters, plan: plan, in: folder, order: [])
            return folder
        }
        log("book \(details.title): \(chapters.count) chapters in \(destination?.displayName ?? "the top level")")
        return folder
    }

    /// *Replace* (decision D13): the book's chapters rebuilt from the file, in the same folder,
    /// which keeps its place in the tree, its name, its order and its listening. The book's
    /// chapters are the pages its record names (`BookSourceState.chapterKeys`), wherever they
    /// have been moved (decision D19). A chapter is carried over from the page it was:
    /// - the page with its key, wherever it is, stays there, in its place in the order. With the
    ///   same listen text it keeps everything: position, finished, audio. With other text it keeps
    ///   its audio where paragraphs match (aligned by text), and its position only if the
    ///   paragraph it is in is still there, word for word; it is no longer finished (a finished
    ///   one starts again from its top), and playback of it stops, as does a session a waiting
    ///   merge would move onto it (`keysWaitingToMerge`);
    /// - otherwise one of the book's chapters with the same listen text, under another key, hands
    ///   over its place, position and audio (merged under the new key), and a session playing it
    ///   follows;
    /// - otherwise it is new, and goes into the book beside the chapter before it (`slot`).
    ///
    /// The book's chapters no chapter comes from are deleted if they are still in the book, after
    /// playback of them stops (and of a session a waiting merge would move onto them); their
    /// audio goes once the save succeeds (audio work, `planDelete`), so a save that fails leaves
    /// every page and its audio as they were. One moved out of the book stays where it was put.
    /// Pages moved into the book from elsewhere are never touched.
    /// It is one edit (`edit`): a save that fails is rolled back and throws
    /// `LibraryStoreError.saveFailed`, and the book reads as it did.
    /// The book's place follows its page; when that page goes, it moves to the nearest page before
    /// it in the book's order that stays, as deleting a page moves it (none if no earlier page
    /// stays).
    func replaceBook(_ folder: Folder, with details: FolderDetails, chapters: [PageContent]) throws {
        let shown = playOrder(of: folder)
        let order = pages(in: folder, sort: .manual)
        let place = folder.currentPageKey
        let plan = replacement(of: recordedChapters(of: folder), in: folder, with: chapters)
        // Playback of a chapter that goes or changes stops before anything changes, and so does a
        // session a waiting merge would move onto one (`keysWaitingToMerge`), so no page changes
        // under a session; the position stopping records is saved on its own. The edit keeps the
        // replacement whole: nothing commits while it is staged.
        stopPlayback(changedBy: plan, chapters: chapters)

        try edit("replace book") {
            for page in plan.dropped { dropChapter(page) }
            apply(details, chapters: chapters, to: folder)
            stageChapters(chapters, plan: plan, in: folder, order: order)
            folder.currentPageKey = Self.place(place, in: shown, after: plan, chapters: chapters)
        }
        log("book \(folder.name) replaced: \(chapters.count) chapters, \(plan.byKey.count) by key, \(plan.byText.count) by text, \(plan.dropped.count) dropped")
    }

    /// Books stored before they kept a record of their chapters (`BookSourceState.chapterKeys`)
    /// get one, once, from the pages in them in their order: those pages are the chapters their
    /// file gave. Saves; a save that fails is rolled back, and the next launch records them.
    /// Returns how many books were recorded.
    @discardableResult
    func recordBookChapters() -> Int {
        let book = FolderKind.book.rawValue
        let books = (try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.kindRaw == book }))) ?? []
        var recorded = 0
        for folder in books where folder.bookState?.chapterKeys == nil {
            var state = folder.bookState ?? BookSourceState()
            state.chapterKeys = pages(in: folder, sort: .manual).compactMap(\.key)
            folder.sourceStateData = try? JSONEncoder().encode(state)
            recorded += 1
        }
        guard recorded > 0 else { return 0 }
        guard commit("record book chapters") else {
            rollBack()
            log("record book chapters: save failed, rolled back; the next launch records them")
            return 0
        }
        log("recorded the chapters of \(recorded) book(s)")
        return recorded
    }

    /// The book's chapters from its last import, wherever they are now: the pages its record
    /// names, or, without a record (`recordBookChapters` couldn't save), the pages in it.
    private func recordedChapters(of folder: Folder) -> [Page] {
        guard let keys = folder.bookState?.chapterKeys else { return pages(in: folder, sort: .manual) }
        return keys.compactMap(page(key:))
    }

    /// Stops playback of every chapter `plan` drops or changes the text of, and of a session a
    /// waiting merge would move onto one.
    private func stopPlayback(changedBy plan: Replacement, chapters: [PageContent]) {
        let changing = plan.dropped.compactMap(\.key)
            + plan.byKey.filter { !Self.reads($0.value, as: chapters[$0.key]) }.compactMap { $0.value.key }
        for key in changing + keysWaitingToMerge(into: Set(changing)) { stopPlaybackIfPlaying(key) }
    }

    /// `folder`'s pages in `sort`.
    private func pages(in folder: Folder, sort: PageSort) -> [Page] {
        (try? context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: sort))) ?? []
    }

    /// Which page each chapter comes from (decision D13).
    private struct Replacement {
        /// Chapter index → the page with its key, wherever it is.
        var byKey: [Int: Page] = [:]
        /// Chapter index → one of the book's chapters with its listen text under another key.
        var byText: [Int: Page] = [:]
        /// The book's chapters no chapter comes from that are still in the book.
        var dropped: [Page] = []
    }

    /// `old`: the book's chapters from its last import, wherever they are; `folder`: the book.
    private func replacement(of old: [Page], in folder: Folder?, with chapters: [PageContent]) -> Replacement {
        var plan = Replacement()
        var claimed = Set<ObjectIdentifier>()
        for (index, chapter) in chapters.enumerated() {
            if let page = page(key: chapter.ref.key), claimed.insert(ObjectIdentifier(page)).inserted {
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
        plan.dropped = old.filter { !claimed.contains(ObjectIdentifier($0)) && folder != nil && $0.folder === folder }
        return plan
    }

    /// Writes `chapters` by `plan`, the book being `folder`, whose pages were `order` (its manual
    /// order) before: a chapter's own page stays where it is; one carried over from a page under
    /// another key takes that page's folder and place; the rest go into the book (`slot`).
    private func stageChapters(_ chapters: [PageContent], plan: Replacement, in folder: Folder, order: [Page]) {
        let dropped = Set(plan.dropped.map(ObjectIdentifier.init))
        var order = order.filter { !dropped.contains(ObjectIdentifier($0)) }
        var pages: [Page] = []
        var newcomers: [Page] = []
        for (index, chapter) in chapters.enumerated() {
            if let page = plan.byKey[index] {
                updateChapter(page, to: chapter, byline: folder.byline)
                if !page.isInLibrary {
                    page.addedAt = now()
                    newcomers.append(page)
                }
                pages.append(page)
            } else if let from = plan.byText[index] {
                let page = makeChapter(chapter, byline: folder.byline)
                carryListening(from: from, to: page)
                if let fromKey = from.key {
                    planMerge(from: fromKey, into: chapter.ref.key, fromParagraphs: from.cachedListenParagraphs ?? [],
                              paragraphs: chapter.document.paragraphs)
                }
                if from.isInLibrary {
                    page.sortKey = from.sortKey
                    page.setFolder(from.folder)
                    if let at = order.firstIndex(where: { $0 === from }) { order[at] = page }
                    if let other = from.folder, other !== folder, other.currentPageKey == from.key {
                        other.currentPageKey = chapter.ref.key
                    }
                } else {
                    newcomers.append(page)
                }
                context.delete(from)
                pages.append(page)
            } else {
                let page = makeChapter(chapter, byline: folder.byline)
                newcomers.append(page)
                pages.append(page)
            }
        }
        slot(newcomers, among: pages, into: folder, order: &order)
    }

    /// Files `newcomers` into `folder`, whose pages are `order` (its manual order): each just
    /// after the chapter before it (in `chapters`, the book's order) that is in the folder, else
    /// just before the next one that is, else at the end. A book never reordered keeps the
    /// file's order; one reordered keeps yours, each new chapter beside its neighbour.
    private func slot(_ newcomers: [Page], among chapters: [Page], into folder: Folder, order: inout [Page]) {
        var filed = Set(order.map(ObjectIdentifier.init))
        for page in newcomers {
            guard let index = chapters.firstIndex(where: { $0 === page }) else { continue }
            let before: Page?
            if let previous = chapters[..<index].last(where: { filed.contains(ObjectIdentifier($0)) }),
               let at = order.firstIndex(where: { $0 === previous }) {
                before = order.indices.contains(at + 1) ? order[at + 1] : nil
            } else {
                before = chapters[(index + 1)...].first { filed.contains(ObjectIdentifier($0)) }
            }
            FractionalOrder.move([page], among: order, before: before, key: \.sortKey)
            order.insert(page, at: before.flatMap { b in order.firstIndex { $0 === b } } ?? order.count)
            filed.insert(ObjectIdentifier(page))
            page.setFolder(folder)
        }
    }

    /// The book's place after *Replace*: its page's key now (a chapter carried over to a new key
    /// takes that key), or, when that page goes, the key of the nearest page before it in `shown`
    /// (the book's pages as they played before) that stays; nil when none does.
    private static func place(_ place: UUID?, in shown: [Page], after plan: Replacement,
                              chapters: [PageContent]) -> UUID? {
        guard let place, let at = shown.firstIndex(where: { $0.key == place }) else { return nil }
        let dropped = Set(plan.dropped.map(ObjectIdentifier.init))
        var renamed: [ObjectIdentifier: UUID] = [:]
        for (index, page) in plan.byText { renamed[ObjectIdentifier(page)] = chapters[index].ref.key }
        return shown[...at].reversed().lazy.compactMap { page -> UUID? in
            dropped.contains(ObjectIdentifier(page)) ? nil : renamed[ObjectIdentifier(page)] ?? page.key
        }.first
    }

    // MARK: - Pieces

    /// The file's details, and the record of its chapters (`BookSourceState.chapterKeys`).
    private func apply(_ details: FolderDetails, chapters: [PageContent], to folder: Folder) {
        folder.byline = details.byline
        folder.coverData = details.cover
        folder.sourceURLString = details.sourceURL?.absoluteString
        folder.sourceIdentifier = details.sourceIdentifier
        var state = details.sourceState.flatMap { try? JSONDecoder().decode(BookSourceState.self, from: $0) }
            ?? BookSourceState()
        state.chapterKeys = chapters.map(\.ref.key)
        folder.sourceStateData = try? JSONEncoder().encode(state)
    }

    /// A new chapter page, in no folder yet.
    private func makeChapter(_ chapter: PageContent, byline: String?) -> Page {
        let page = Page(key: chapter.ref.key, title: chapter.title, byline: byline ?? "", urlString: nil,
                        contentState: .saved, addedAt: now())
        context.insert(page)
        fillChapter(page, from: chapter)
        return page
    }

    /// Whether `page` reads as `chapter` reads: the same listen paragraphs.
    private static func reads(_ page: Page, as chapter: PageContent) -> Bool {
        (page.cachedListenParagraphs ?? page.listenDocument().paragraphs) == chapter.document.paragraphs
    }

    /// A chapter's page keeps its listening when its text is unchanged; otherwise see
    /// `replaceBook`.
    private func updateChapter(_ page: Page, to chapter: PageContent, byline: String?) {
        let old = page.cachedListenParagraphs ?? page.listenDocument().paragraphs
        let new = chapter.document
        page.byline = byline ?? ""
        if old == new.paragraphs {
            fillChapter(page, from: chapter)
            return
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
    }

    /// A chapter of the book no chapter comes from: the page goes in this save; its audio once the save
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


extension Folder {
    /// A book's record of its file and its chapters (`sourceStateData`); nil without one.
    var bookState: BookSourceState? {
        sourceStateData.flatMap { try? JSONDecoder().decode(BookSourceState.self, from: $0) }
    }
}
