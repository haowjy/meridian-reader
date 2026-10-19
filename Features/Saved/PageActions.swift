import SwiftData
import SwiftUI

/// "This page", wherever it shows: a Library row, a Favorites tile, a History visit, the Now
/// Playing bar, the Reader, Now Playing and the browser. What it is (saved, a favorite, its
/// download) and what its menu (`PageMenu`), 🔖, ☆ and the Move tree do with it are decided here
/// once. The places keep only what differs: the browser extracts its page before it saves it and
/// stars it with the web view's title and icon (`loaded`), and Now Playing adds *Go to*.
///
/// `page` is the page's Library page by the one rule, address first, then key
/// (`LibraryStore.page(key:canonicalURL:)`; on screen, live, `PageLookup`). *Remove from Library*
/// removes that page and Save saves into it, so 🔖's look and what tapping it does always agree.
@MainActor
struct PageActions {
    /// The page as text (the Reader's article, Now Playing's content). nil elsewhere: a Library
    /// page's text is read from it only when it is saved, and the browser extracts its page.
    let article: ReaderArticle?
    /// The page's web address; nil for a chapter that has none.
    let url: URL?
    /// The page's Library page, saved or not (a link, played without saving), if it has one.
    let page: Page?
    /// The browser's page, which is text only once extracted.
    let loaded: LoadedPage?
    let library: LibraryStore
    let shell: ShellState
    let speech: SpeechController
    let downloads: DownloadCenter
    let follow: FollowCenter

    /// The browser's page before it is extracted: Save extracts it first, and ☆ takes the web
    /// view's title and icon.
    struct LoadedPage {
        /// It can be extracted now (a page is up and nothing else is extracting it).
        var canSave: Bool
        /// Extracts the page and saves it into the folder (nil: the top level).
        var save: (Folder?) -> Void
        var toggleFavorite: () -> Void
    }

    /// `url` nil: the article's address, else the page's.
    init(page: Page?, article: ReaderArticle? = nil, url: URL? = nil, loaded: LoadedPage? = nil,
         library: LibraryStore, shell: ShellState, speech: SpeechController, downloads: DownloadCenter,
         follow: FollowCenter) {
        self.article = article
        self.url = url ?? article?.origin.url ?? page?.url
        self.page = page
        self.loaded = loaded
        self.library = library
        self.shell = shell
        self.speech = speech
        self.downloads = downloads
        self.follow = follow
    }

    // MARK: - State

    /// The page when it is saved in the Library (🔖 filled).
    var savedPage: Page? { page.flatMap { $0.isSavedToLibrary ? $0 : nil } }
    var isSaved: Bool { savedPage != nil }
    /// In the Library (saved, or a link there such as a story's chapter): its menu offers
    /// *Remove from Library*, *Move to…* and *Download*.
    var isInLibrary: Bool { page?.isInLibrary == true }
    var isFavorite: Bool { page?.isFavorite == true }
    /// ☆ as the Library offers it: a web page, or a page in the Library (a chapter too).
    var canFavorite: Bool { url.map(LibraryStore.canFavorite) == true || page.map(LibraryStore.canFavorite) == true }
    var shareURL: URL? { url.flatMap { $0.isWeb ? $0 : nil } }
    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    var websiteURL: URL? {
        guard let url, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }
    /// Where its download stands (`DownloadCenter.state(of:)`): downloading or downloaded, its
    /// menu offers *Remove Download*.
    var hasDownload: Bool { page.map { downloads.state(of: $0) != .notDownloaded } == true }
    /// There is text to save: the article's, the page's own (not a link's), or the browser's page
    /// once extracted.
    var canSave: Bool {
        if let loaded { return loaded.canSave }
        if let article { return !article.document.isEmpty }
        return page.map { !$0.isLink } == true
    }
    /// The save rows' face: *Save to Library* / *Save to Folder…* while the Library hasn't the
    /// page's text (out of it, or a link in it shown where its text is: the browser, the Reader),
    /// else *Remove from Library* / *Move to…*. 🔖 reads the same (`isSaved`) and does the same.
    var offersSave: Bool { !isSaved && (loaded != nil || canSave || !isInLibrary) }

    // MARK: - Actions

    /// *Read*: the page in the Reader (Now Playing when it is what you hear), a link in the
    /// browser (`LibraryActions.open`); an address the Library hasn't, in the browser. A sheet
    /// it was opened from (History) closes.
    func read() {
        shell.sheet = nil
        if let page {
            libraryActions.open(page)
        } else if let url {
            shell.navigate(to: url)
        }
    }

    /// 🔖 / *Save to Library* / *Remove from Library*: saves the page into the Library's top
    /// level, or removes it. Neither touches the screen; Save never touches playback, and Remove
    /// stops the page only if you hear it. A change that can't be stored leaves it as it was, and
    /// a toast says so.
    func toggleSaved() {
        if offersSave {
            save(.keep)
        } else {
            remove()
        }
    }

    /// *Remove from Library* / *Remove from Recent* (🔖 on a saved page, menus): the Library's one
    /// remove (`LibraryActions.remove`). Its star, audio and spot stay; if it is the page you
    /// hear, playback stops, and Now Playing closes.
    func remove() {
        guard let page else { return }
        libraryActions.remove([page])
    }

    /// 🔖 held (*Save to Folder…*), and the menu row that reads *Save to Folder…* while the page's
    /// text isn't kept (`offersSave`) and *Move to…* after: the Move tree. The page is saved into the folder
    /// picked, or moves there; one that can't be stored keeps the tree up, with a toast saying so.
    func saveToFolder() {
        if !offersSave, let page {
            libraryActions.move([.page(page)])
            return
        }
        guard canSave else { return }
        shell.present(.moveTo(MoveRequest(title: Verbs.title(Verbs.saveToFolder), current: nil) { [self] folder in
            save(.folder(folder))
        }))
    }

    /// ☆: in or out of Favorites (`FavoriteFlow`). A web page by its address, so a new favorite
    /// keeps the article's icon; a chapter (no address) as the Library row's ☆ does.
    func toggleFavorite() {
        if let loaded { return loaded.toggleFavorite() }
        let flow = FavoriteFlow(library: library, shell: shell)
        if let url, LibraryStore.canFavorite(url) {
            flow.toggle(url: url, title: article?.title ?? page?.givenTitle, artwork: article?.artwork ?? page?.artworkData) {
                await FaviconFetcher.best(for: url, webView: nil)
            }
        } else if let page {
            flow.toggle(page)
        }
    }

    /// *Download* / *Remove Download*: *Remove Download* takes the page out of every download and
    /// keeps it out (`DownloadCenter.deleteDownloads(of:)`, P8).
    func toggleDownload() {
        guard let page, page.isInLibrary else { return }
        if hasDownload {
            downloads.deleteDownloads(of: page)
        } else {
            DownloadActions(downloads: downloads, shell: shell).download(page)
        }
    }

    func share() {
        if let shareURL { shell.present(.share(shareURL)) }
    }

    var libraryActions: LibraryActions {
        LibraryActions(library: library, speech: speech, shell: shell, follow: follow)
    }

    /// Saves the page through the one save path (`.keep`: where the Library has it, else the top
    /// level; `.folder`: picked in the Move tree); false once a toast has said it couldn't. The
    /// browser's page is extracted first and reports its own failure. A save under an older
    /// page's key gives the Reader showing the article that key.
    @discardableResult
    private func save(_ placement: SavePlacement) -> Bool {
        if let loaded {
            loaded.save(placement.folder)
            return true
        }
        guard let article = textToSave else { return false }
        // Asked again at the pick: the page may have been saved meanwhile.
        if case .folder(let folder) = placement,
           let saved = library.savedPage(key: article.id, canonicalURL: article.origin.canonicalURL) {
            return shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(saved)], to: folder) } != nil
        }
        guard let key = shell.attempt(String(localized: "Couldn’t save"), {
            try ArticleSaveCoordinator(library: library, speech: speech).save(article, placement: placement)
        }) else { return false }
        if key != article.id { shell.updateReader(id: article.id) { $0.id = key } }
        return true
    }

    /// The text Save stores: the article on screen, else the page's own (its listen blocks when
    /// it has none built).
    private var textToSave: ReaderArticle? {
        if let article { return article.document.isEmpty ? nil : article }
        guard let page, !page.isLink else { return nil }
        var article = ReaderArticle(page: page)
        if article.document.isEmpty { article.document = page.listenDocument() }
        return article
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
