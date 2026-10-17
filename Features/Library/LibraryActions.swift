import SwiftUI

/// What the Library's rows, headers and Edit's bar do, in one place: open a page (the
/// Reader, Now Playing when it is what you hear, the browser for a link), play a page or a book,
/// mark and remove pages, delete folders, file things with the Move tree. Opening never plays,
/// and playing never navigates. Each edit is one save: one that can't be saved changes nothing
/// and shows a toast, and what follows its success runs only after the save.
@MainActor
struct LibraryActions {
    let library: LibraryStore
    let speech: SpeechController
    let shell: ShellState

    // MARK: - Pages

    /// A saved page in the Reader sheet (Now Playing if it is what you hear); a link in
    /// the browser.
    func open(_ page: Page) {
        if page.isLink {
            if let url = page.url { shell.navigate(to: url) }
            return
        }
        shell.openSaved(page.listenKey, in: library)
    }

    func playState(of page: Page) -> PlayState {
        speech.playState(of: .page(page.listenKey))
    }

    /// What `page`'s row shows: its length or time left at the current speed, finished, skipped.
    func progress(of page: Page) -> ListRow.Progress {
        PageProgress.of(page, rate: speech.rateMultiplier)
    }

    /// The row's ▶: pause or resume it when it is what you hear; otherwise play it from its spot
    /// (a finished page from the top), replacing what plays. A page in a folder carries on through
    /// it.
    func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.start(.page(page), at: page.listenStart)
        }
    }

    /// *Play from Here* on a page in a folder: from its start, carrying on through the folder.
    func playFromStart(_ page: Page) {
        speech.playPage(page.listenKey)
    }

    /// *Save* on a page played without saving (decision D5): into the Library's top level
    /// through the one save path, its audio kept and playback untouched. False when it couldn't
    /// be saved (a toast says so).
    @discardableResult
    func save(_ page: Page) -> Bool {
        var article = ReaderArticle(page: page)
        if article.document.isEmpty { article.document = page.listenDocument() }
        return shell.attempt(String(localized: "Couldn’t save")) {
            try ArticleSaveCoordinator(library: library, speech: speech).save(article)
        } != nil
    }

    func share(_ page: Page) {
        guard let url = page.url, url.isWeb else { return }
        shell.present(.share(url))
    }

    // MARK: - Folders

    func playState(of folder: Folder) -> PlayState {
        speech.playState(of: .folder(folder.id))
    }

    /// What `folder`'s row and its header show, `pages` being its pages in play order: with the
    /// page playing when one of them is what you hear, and its time left at the current speed.
    func progress(of folder: Folder, pages: [Page]) -> FolderProgress {
        FolderProgress(folder: folder, pages: pages,
                       playingKey: playState(of: folder).isCurrent ? speech.activeSessionID : nil,
                       rate: speech.rateMultiplier, library: library)
    }

    /// A folder's ▶ and its screen's round button (a book, a series, a folder you
    /// made): pause or resume while one of its pages is what you hear; otherwise Continue from
    /// its place (`LibraryStore.continueStart`), carrying on page to page in its order.
    func playFolder(_ folder: Folder) {
        speech.press(.folder(folder.id)) {
            guard let start = library.continueStart(of: folder) else { return }
            speech.start(.page(start.page), at: start.spot)
        }
    }

    /// *Play from Start*: the first page that plays, from its top.
    func playFolderFromStart(_ folder: Folder) {
        guard case .ready(let key) = ChapterAdvance.start(library.chapterSnapshot(of: folder), place: nil) else { return }
        speech.playPage(key)
    }

    // MARK: - Marks and removing

    /// *Mark as Finished* / *Mark as Unfinished*, Edit's *Mark Finished*. False when it couldn't
    /// be saved (nothing changed; a toast says so).
    @discardableResult
    func setFinished(_ pages: [Page], _ finished: Bool) -> Bool {
        shell.attempt(finished ? String(localized: "Couldn’t mark as finished") : String(localized: "Couldn’t mark as unfinished")) {
            try library.setFinished(pages, finished)
        } != nil
    }

    /// *Mark All Above as Finished* on a page in a folder.
    func markAllAbove(_ page: Page) {
        shell.attempt(String(localized: "Couldn’t mark as finished")) { try library.markAllAbove(page) }
    }

    /// *Skip in Playback* / *Play in Playback* on a page in a folder.
    func toggleSkipsInPlayback(_ page: Page) {
        shell.attempt(String(localized: "Couldn’t change Skip in Playback")) {
            try library.setSkipsInPlayback(page, !page.skipsInPlayback)
        }
    }

    /// *Remove from Library* from every path (a row's menu and swipe, Edit's *Remove*, and through
    /// `PageActions` 🔖 and the browser's, the Reader's and Now Playing's ⋯), all of `pages` in one
    /// save (`LibraryStore.remove`: the star stays). False when it couldn't be saved: none
    /// removed, and a toast says so.
    @discardableResult
    func remove(_ pages: [Page]) -> Bool {
        shell.attempt(String(localized: "Couldn’t remove")) { try library.remove(pages) } != nil
    }

    // MARK: - Edit

    /// The folders and pages Edit's selection on `screen` names.
    func selected(in screen: LibraryScreenState) -> (folders: [Folder], pages: [Page]) {
        var folders: [Folder] = []
        var pages: [Page] = []
        for item in screen.selection {
            switch item {
            case .folder(let id): if let folder = library.folder(id: id) { folders.append(folder) }
            case .page(let key): if let page = library.page(key: key) { pages.append(page) }
            }
        }
        return (folders, pages)
    }

    /// Edit's *Remove*: the selected pages leave the Library in one save, and leave the
    /// selection; the selected folders then wait for the delete question, still selected until
    /// their delete is saved (`deleteFolders`) and still selected if it is cancelled. Pages that
    /// can't be removed leave everything as it was, the selection too, and nothing is asked.
    func removeSelection(of screen: LibraryScreenState) {
        let (folders, pages) = selected(in: screen)
        guard remove(pages) else { return }
        screen.selection = Set(folders.map { LibraryItemID.folder($0.id) })
        screen.confirmDelete(folders)
    }

    /// The delete question's answer (`libraryDialogs`): once the delete is saved, Edit ends, its
    /// selection with it. A delete that can't be saved changes nothing: a toast says so, and Edit
    /// keeps its selection. False then.
    @discardableResult
    func deleteFolders(_ folders: [Folder], in screen: LibraryScreenState) -> Bool {
        guard shell.attempt(String(localized: "Couldn’t delete"), {
            try library.deleteFolders(folders)
        }) != nil else { return false }
        screen.endEditing()
        return true
    }

    // MARK: - Filing

    /// The Move tree for `items`; picking a place moves them there, and `onMoved` runs once the
    /// move is saved. A move that can't be saved changes nothing and leaves the tree up, and a
    /// toast says so.
    func move(_ items: [LibraryItem], onMoved: @escaping () -> Void = {}) {
        guard !items.isEmpty else { return }
        let current: MoveRequest.Place?
        switch items.first {
        case .folder(let folder)?: current = folder.parent.map { .folder($0.id) } ?? .topLevel
        case .page(let page)?: current = page.folder.map { .folder($0.id) } ?? .topLevel
        case nil: current = nil
        }
        let moving = Set(items.compactMap { item -> UUID? in
            if case .folder(let folder) = item { return folder.id }
            return nil
        })
        let library = library
        let shell = shell
        shell.present(.moveTo(MoveRequest(title: String(localized: "Move to…"), current: items.count == 1 ? current : nil,
                                          moving: moving) { destination in
            guard shell.attempt(String(localized: "Couldn’t move"), { try library.move(items, to: destination) }) != nil
            else { return false }
            onMoved()
            return true
        }))
    }
}

// MARK: - Dragging

extension LibraryActions {
    /// The folder or page a dragged row stands for.
    func item(_ id: LibraryItemID) -> LibraryItem? {
        switch id {
        case .folder(let id): library.folder(id: id).map(LibraryItem.folder)
        case .page(let key): library.page(key: key).map(LibraryItem.page)
        }
    }

    /// Whether the row `id` may be dropped into the folder row `row`: what the Move tree allows
    /// (`LibraryStore.moveRefusal`), so never a folder into itself or below itself. False when `row` isn't a folder.
    func canFile(_ id: LibraryItemID, into row: LibraryItemID) -> Bool {
        guard case .folder(let folderID) = row, let folder = library.folder(id: folderID), let item = item(id) else { return false }
        return library.moveRefusal(item, to: folder) == nil
    }

    /// A row dropped on a folder row: filed at the end of that folder, as Move does. False when
    /// it can't go there, or the move couldn't be saved (a toast says so).
    func file(_ id: LibraryItemID, into folderID: UUID) -> Bool {
        guard canFile(id, into: .folder(folderID)), let item = item(id), let folder = library.folder(id: folderID) else { return false }
        return shell.attempt(String(localized: "Couldn’t move")) { try library.move([item], to: folder) } != nil
    }

    /// Whether the row `id` may be placed beside the row `row`: a page beside a page in the
    /// Library, a folder beside a folder, in a container that takes it.
    func canPlace(_ id: LibraryItemID, beside row: LibraryItemID) -> Bool {
        guard let item = item(id), let neighbour = self.item(row) else { return false }
        switch (item, neighbour) {
        case (.page, .page(let page)):
            return page.isInLibrary && library.moveRefusal(item, to: page.folder) == nil
        case (.folder, .folder(let folder)):
            return library.moveRefusal(item, to: folder.parent) == nil
        default:
            return false
        }
    }

    /// A row dropped on the `edge` of the row `row`: placed there among `row`'s siblings
    /// (`LibraryStore.arrange`). A page's folder (or the top level) becomes *Manual*, numbered
    /// first in the order on screen. nil when it was let go where it already is; false when it
    /// can't go there or the change couldn't be saved (a toast says so).
    func place(_ id: LibraryItemID, beside row: LibraryItemID, edge: VerticalEdge) -> Bool? {
        guard canPlace(id, beside: row), let item = item(id), let neighbour = self.item(row) else { return false }
        switch (item, neighbour) {
        case (.page(let page), .page(let other)):
            let folder = other.folder
            let sort = folder?.pageSort ?? LibraryTopLevel.sort
            let siblings = folder.map { library.pages(in: $0) } ?? library.loosePages(sort: sort)
            guard case .before(let before) = LibraryDropSlot.placement(of: page, beside: other, edge: edge, siblings: siblings)
            else { return nil }
            let placed = shell.attempt(String(localized: "Couldn’t change the order")) {
                try library.arrange([page], in: folder, before: before, shownIn: sort)
            } != nil
            if placed, folder == nil { LibraryTopLevel.sort = .manual }
            return placed
        case (.folder(let folder), .folder(let other)):
            let parent = other.parent
            let siblings = parent.map(library.subfolders(of:)) ?? library.topLevelFolders()
            guard case .before(let before) = LibraryDropSlot.placement(of: folder, beside: other, edge: edge, siblings: siblings)
            else { return nil }
            return shell.attempt(String(localized: "Couldn’t change the order")) {
                try library.arrange([folder], in: parent, before: before)
            } != nil
        default:
            return false
        }
    }
}

extension Folder {
    /// The symbol a folder row shows when it has no cover.
    var rowSymbol: String {
        hasDetails ? Icons.book : Icons.folder
    }
}
