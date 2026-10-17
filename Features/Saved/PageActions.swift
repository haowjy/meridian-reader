import SwiftData
import SwiftUI

/// "This page" in the Reader, Now Playing and the browser: whether it is saved and a favorite,
/// what it can share and open, and what 🔖, ☆, the Move tree and the page's ⋯ rows do with it.
/// The screens keep only what differs: the browser extracts its page before it saves it, and Now
/// Playing adds *Go to*.
///
/// `page` is the page's Library page by the one rule, address first, then key
/// (`LibraryStore.page(key:canonicalURL:)`; on screen, live, `PageLookup`). *Remove from Library*
/// removes that page and Save saves into it, so 🔖's look and what tapping it does always agree.
@MainActor
struct PageActions {
    /// The page as text (the Reader's article, Now Playing's content). nil in the browser, which
    /// extracts its page first, and in Now Playing while its content can't be found.
    let article: ReaderArticle?
    /// The page's web address; nil for a chapter that has none.
    let url: URL?
    /// The page's Library page, saved or not (a link, played without saving), if it has one.
    let page: Page?
    let library: LibraryStore
    let shell: ShellState
    let speech: SpeechController
    let downloads: DownloadCenter

    init(article: ReaderArticle?, page: Page?, library: LibraryStore, shell: ShellState, speech: SpeechController,
         downloads: DownloadCenter) {
        self.article = article
        self.url = article?.origin.url
        self.page = page
        self.library = library
        self.shell = shell
        self.speech = speech
        self.downloads = downloads
    }

    /// The browser's page, before it is extracted.
    init(url: URL?, page: Page?, library: LibraryStore, shell: ShellState, speech: SpeechController,
         downloads: DownloadCenter) {
        self.article = nil
        self.url = url
        self.page = page
        self.library = library
        self.shell = shell
        self.speech = speech
        self.downloads = downloads
    }

    // MARK: - State

    /// The page when it is saved in the Library (🔖 filled).
    var savedPage: Page? { page.flatMap { $0.isSavedToLibrary ? $0 : nil } }
    var isSaved: Bool { savedPage != nil }
    var isFavorite: Bool { page?.isFavorite == true }
    /// ☆ as the Library offers it: a web page, or a page in the Library (a chapter too).
    var canFavorite: Bool { url.map(LibraryStore.canFavorite) == true || page.map(LibraryStore.canFavorite) == true }
    var shareURL: URL? { url.flatMap { $0.isWeb ? $0 : nil } }
    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    var websiteURL: URL? {
        guard let url, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }
    /// The text is ready to save (an older page builds its listen blocks after it opens).
    var canSave: Bool { article.map { !$0.document.isEmpty } == true }

    // MARK: - The Reader's and Now Playing's ⋯

    /// The page's ⋯ (decision D24). The Reader's has no *Go to*; Now Playing sets it.
    var readerMenu: ReaderMenu {
        ReaderMenu(
            isSaved: isSaved,
            isFavorite: isFavorite,
            save: MenuAvailability(when: canSave),
            moveTo: MenuAvailability(when: isSaved && canSave),
            favorite: MenuAvailability(when: canFavorite),
            share: MenuAvailability(when: shareURL != nil),
            download: MenuAvailability(when: savedPage.map { !downloads.isQueued(.page($0.listenKey)) } == true),
            website: MenuAvailability(when: websiteURL != nil)
        )
    }

    /// A row of that ⋯; `goTo` is Now Playing's *Go to*.
    func perform(_ action: ReaderMenu.Action, goTo: () -> Void = {}) {
        switch action {
        case .goTo: goTo()
        case .settings: shell.present(.settings)
        case .toggleSave: toggleSaved()
        case .moveTo: saveToFolder()
        case .toggleFavorite: toggleFavorite()
        case .share: share()
        case .download: if let savedPage { DownloadActions(downloads: downloads, shell: shell).download(savedPage) }
        case .downloads: shell.present(.downloads)
        case .favorites: shell.showFavorites()
        case .history: shell.present(.history)
        // The article's own web page in the browser, wherever the sheet was opened from.
        // Playback keeps going.
        case .openWebsite: if let websiteURL { shell.openWebsite(websiteURL) }
        }
    }

    // MARK: - Actions

    /// 🔖 / ⋯ → Save: saves the article into the Library's top level, or removes the page from
    /// it. Neither touches the screen or playback; a change that can't be stored leaves 🔖 as it
    /// was, and a toast says so.
    func toggleSaved() {
        if isSaved {
            remove()
        } else if let article, canSave {
            store { try ArticleSaveCoordinator(library: library, speech: speech).save(article) }
        }
    }

    /// *Remove from Library* (🔖 on a saved page, ⋯): the Library rows' own remove
    /// (`LibraryActions.remove`). Its star, audio and spot stay; playback goes on.
    func remove() {
        guard let savedPage else { return }
        LibraryActions(library: library, speech: speech, shell: shell).remove([savedPage])
    }

    /// 🔖's long-press (*Save to Folder…*) and ⋯ → Move to…: the Move tree. The page is saved into
    /// the folder picked, or a saved page moves there; one that can't be stored keeps the tree up,
    /// with a toast saying so.
    func saveToFolder() {
        guard let article, canSave else { return }
        let current: MoveRequest.Place? = savedPage.map { page in page.folder.map { .folder($0.id) } ?? .topLevel }
        let title = current != nil ? String(localized: "Move to…") : String(localized: "Save to…")
        shell.present(.moveTo(MoveRequest(title: title, current: current) { [self] folder in
            // Asked again at the pick: the page may have been saved or removed meanwhile.
            if let saved = library.savedPage(key: article.id, canonicalURL: article.origin.canonicalURL) {
                return shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(saved)], to: folder) } != nil
            }
            return store {
                try ArticleSaveCoordinator(library: library, speech: speech).save(article, placement: .folder(folder))
            }
        }))
    }

    /// ☆: in or out of Favorites (`FavoriteFlow`). A web page by its address, so a new favorite
    /// keeps the article's icon; a chapter (no address) as the Library row's ☆ does.
    func toggleFavorite() {
        let flow = FavoriteFlow(library: library, shell: shell)
        if let url, LibraryStore.canFavorite(url) {
            flow.toggle(url: url, title: article?.title, artwork: article?.artwork) {
                await FaviconFetcher.best(for: url, webView: nil)
            }
        } else if let page {
            flow.toggle(page)
        }
    }

    func share() {
        if let shareURL { shell.present(.share(shareURL)) }
    }

    /// Stores a save; false once a toast has said it couldn't. A save under an older page's key
    /// gives the Reader showing the article that key.
    private func store(_ save: () throws -> UUID) -> Bool {
        guard let article, let key = shell.attempt(String(localized: "Couldn’t save"), save) else { return false }
        if key != article.id { shell.updateReader(id: article.id) { $0.id = key } }
        return true
    }
}

extension LibraryStore {
    /// The page for `key` and `canonicalURL` by `page(key:canonicalURL:)`, when it is saved in
    /// the Library.
    func savedPage(key: UUID, canonicalURL: String?) -> Page? {
        guard let page = page(key: key, canonicalURL: canonicalURL), page.isSavedToLibrary else { return nil }
        return page
    }
}

/// The Library page a screen's page is, live: its address first, then its key, the rule
/// `LibraryStore.page(key:canonicalURL:)` follows. Two one-row queries, so the screen follows a
/// save, a remove or a ☆ made anywhere, and reads nothing else.
struct PageLookup<Content: View>: View {
    @Query private var byAddress: [Page]
    @Query private var byKey: [Page]
    private let content: (Page?) -> Content

    /// `key` nil or `canonicalURL` nil: that half finds nothing (no page has an empty address or
    /// the nil UUID).
    init(key: UUID?, canonicalURL: String?, @ViewBuilder content: @escaping (Page?) -> Content) {
        _byAddress = Query(Self.byAddress(canonicalURL ?? ""))
        _byKey = Query(LibraryQueries.page(key: key ?? Self.noKey))
        self.content = content
    }

    var body: some View {
        content(Self.page(byAddress: byAddress.first, byKey: byKey.first))
    }

    private static var noKey: UUID { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) }

    /// The oldest page for the address, as `LibraryStore.page(canonicalURL:)` reads it.
    static func byAddress(_ canonicalURL: String) -> FetchDescriptor<Page> {
        var descriptor = LibraryQueries.pages(canonicalURL: canonicalURL)
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func page(byAddress: Page?, byKey: Page?) -> Page? {
        byAddress ?? byKey
    }
}
