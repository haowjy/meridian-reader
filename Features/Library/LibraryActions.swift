import SwiftUI

/// What the Library's rows, cards and headers do, in one place: open a page (the Reader, Now
/// Playing when it is what you hear, the browser for a link), play a page or a book, file things
/// with the Move tree. Opening never plays, and playing never navigates.
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

    // MARK: - Filing

    /// The Move tree for `items`; picking a place moves them there.
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
        shell.present(.moveTo(MoveRequest(title: String(localized: "Move to…"), current: items.count == 1 ? current : nil,
                                          moving: moving) { destination in
            try? library.move(items, to: destination)
            onMoved()
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
