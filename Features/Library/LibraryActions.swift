import SwiftUI

/// What the Library's rows, cards, headers and Edit's bar do, in one place: open a page (the
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

    /// A saved page or chapter in the Reader sheet (Now Playing if it is what you hear); a link in
    /// the browser. From the Favorites sheet the sheet goes first.
    func open(_ page: Page) {
        if case .favorites = shell.sheet { shell.sheet = nil }
        if page.isLink {
            if let url = page.url { shell.navigate(to: url) }
            return
        }
        shell.openSaved(page.listenKey, in: library)
    }

    func playState(of page: Page) -> PlayState {
        speech.playState(of: .page(page.listenKey))
    }

    /// The row's ▶: pause or resume it when it is what you hear; otherwise play it from its spot
    /// (a finished page from the top), replacing what plays. A chapter carries on through its book.
    func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            let fromTop = page.finishedAt != nil
            speech.toggle(.page(page), resumeParagraph: fromTop ? 0 : page.positionParagraph,
                          resumeUTF16Offset: fromTop ? 0 : page.positionUTF16)
        }
    }

    /// *Play from Here* on a chapter: from its start.
    func playFromStart(_ page: Page) {
        speech.playPage(page.listenKey)
    }

    func share(_ page: Page) {
        guard let url = page.url, url.isWeb else { return }
        shell.present(.share(url))
    }

    // MARK: - Books and series

    func playState(of folder: Folder) -> PlayState {
        speech.playState(of: .folder(folder.id))
    }

    /// The book's round button: pause or resume while one of its chapters is what you hear;
    /// otherwise Continue from its place (`LibraryStore.continueStart`).
    func playBook(_ folder: Folder) {
        speech.press(.folder(folder.id)) {
            guard let start = library.continueStart(of: folder) else { return }
            speech.toggle(.page(start.page), resumeParagraph: start.paragraph, resumeUTF16Offset: start.utf16Offset)
        }
    }

    /// *Play from Start*: the first chapter that plays, from its top.
    func playBookFromStart(_ folder: Folder) {
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

    /// *Mark All Above as Finished* on a chapter.
    func markAllAbove(_ page: Page) {
        shell.attempt(String(localized: "Couldn’t mark as finished")) { try library.markAllAbove(page) }
    }

    /// *Skip in Playback* / *Play in Playback* on a chapter.
    func toggleSkipsInPlayback(_ page: Page) {
        shell.attempt(String(localized: "Couldn’t change Skip in Playback")) {
            try library.setSkipsInPlayback(page, !page.skipsInPlayback)
        }
    }

    /// *Remove from Library* (a row's menu and swipe, Edit's *Remove*), all of `pages` in one
    /// save. False when it couldn't be saved: none removed, and a toast says so.
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
    func deleteFolders(_ folders: [Folder], keepContents: Bool, in screen: LibraryScreenState) -> Bool {
        guard shell.attempt(String(localized: "Couldn’t delete"), {
            try library.deleteFolders(folders, keepContents: keepContents)
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

extension Folder {
    /// The symbol a folder row shows when it has no cover.
    var rowSymbol: String {
        switch kind {
        case .favorites: "star.fill"
        case .book: "book.closed"
        case .series: "books.vertical"
        case .plain: "folder"
        }
    }

    /// Subfolders and pages directly inside.
    var itemCount: Int { (children?.count ?? 0) + (pages?.count ?? 0) }
}
