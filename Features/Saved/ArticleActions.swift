import SwiftData
import SwiftUI

/// "This page", wherever it shows: a Library row, a Favorites tile, a History visit, the Now
/// Playing bar, the Reader, Now Playing and the browser. What it is (saved, a favorite, its
/// download) and what its menu (`ArticleMenu`), 🔖, ☆ and the Move tree do with it are decided here
/// once. The places keep only what differs: the browser extracts its page before it saves it and
/// stars it with the web view's title and icon (`loaded`), and Now Playing adds *Go to*.
///
/// `article` is the page's Library page by the one rule, address first, then key
/// (`LibraryStore.article(key:canonicalURL:)`; on screen, live, `ArticleLookup`). *Remove from Library*
/// removes that page and Save saves into it, so 🔖's look and what tapping it does always agree.
@MainActor
struct ArticleActions {
    /// The page as text (the Reader's article, Now Playing's content). nil elsewhere: a Library
    /// page's text is read from it only when it is saved, and the browser extracts its page.
    let readerArticle: ReaderArticle?
    /// The page's web address; nil for a chapter that has none.
    let url: URL?
    /// The page's Library page, saved or not (a link, played without saving), if it has one.
    let article: Article?
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
    init(article: Article?, readerArticle: ReaderArticle? = nil, url: URL? = nil, loaded: LoadedPage? = nil,
         library: LibraryStore, shell: ShellState, speech: SpeechController, downloads: DownloadCenter,
         follow: FollowCenter) {
        self.readerArticle = readerArticle
        self.url = url ?? readerArticle?.origin.url ?? article?.url
        self.article = article
        self.loaded = loaded
        self.library = library
        self.shell = shell
        self.speech = speech
        self.downloads = downloads
        self.follow = follow
    }

    // MARK: - State

    /// The page when it is saved in the Library (🔖 filled).
    var savedArticle: Article? { article.flatMap { $0.isSavedToLibrary ? $0 : nil } }
    var isSaved: Bool { savedArticle != nil }
    /// In the Library (saved, or a link there such as a story's chapter): its menu offers
    /// *Remove from Library*, *Move to…* and *Download*.
    var isInLibrary: Bool { article?.isInLibrary == true }
    var isFavorite: Bool { article?.isFavorite == true }
    /// ☆ as the Library offers it: a web page, or a page in the Library (a chapter too).
    var canFavorite: Bool { url.map(LibraryStore.canFavorite) == true || article.map(LibraryStore.canFavorite) == true }
    var shareURL: URL? { url.flatMap { $0.isWeb ? $0 : nil } }
    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    var websiteURL: URL? {
        guard let url, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }
    /// Where its download stands (`DownloadCenter.state(of:)`): downloading or downloaded, its
    /// menu offers *Remove Download*.
    var hasDownload: Bool { article.map { downloads.state(of: $0) != .notDownloaded } == true }
    /// There is text to save: the article's, the page's own (not a link's), or the browser's page
    /// once extracted.
    var canSave: Bool {
        if let loaded { return loaded.canSave }
        if let readerArticle { return !readerArticle.document.isEmpty }
        return article.map { !$0.isLink } == true
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
        if let article {
            libraryActions.open(article)
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
        guard let article else { return }
        libraryActions.remove([article])
    }

    /// 🔖 held (*Save to Folder…*), and the menu row that reads *Save to Folder…* while the page's
    /// text isn't kept (`offersSave`) and *Move to…* after: the Move tree. The page is saved into the folder
    /// picked, or moves there; one that can't be stored keeps the tree up, with a toast saying so.
    func saveToFolder() {
        if !offersSave, let article {
            libraryActions.move([.article(article)])
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
            flow.toggle(url: url, title: readerArticle?.title ?? article?.givenTitle, artwork: readerArticle?.artwork ?? article?.artworkData) {
                await FaviconFetcher.best(for: url, webView: nil)
            }
        } else if let article {
            flow.toggle(article)
        }
    }

    /// *Download* / *Remove Download*: *Remove Download* takes the page out of every download and
    /// keeps it out (`DownloadCenter.deleteDownloads(of:)`, P8).
    func toggleDownload() {
        guard let article else { return }
        // Downloading saves it (C104): a page played without saving goes into the Library first.
        if !article.isInLibrary {
            guard article.isSaved, shell.attempt(String(localized: "Couldn’t save"), { try library.saveUnsaved(article) }) != nil
            else { return }
        }
        if hasDownload {
            downloads.deleteDownloads(of: article)
        } else {
            DownloadActions(downloads: downloads, shell: shell).download(article)
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
        guard let readerArticle = textToSave else { return false }
        // Asked again at the pick: the page may have been saved meanwhile.
        if case .folder(let folder) = placement,
           let saved = library.savedArticle(key: readerArticle.id, canonicalURL: readerArticle.origin.canonicalURL) {
            return shell.attempt(String(localized: "Couldn’t move")) { try library.move([.article(saved)], to: folder) } != nil
        }
        guard let key = shell.attempt(String(localized: "Couldn’t save"), {
            try ArticleSaveCoordinator(library: library, speech: speech).save(readerArticle, placement: placement)
        }) else { return false }
        if key != readerArticle.id { shell.updateReader(id: readerArticle.id) { $0.id = key } }
        return true
    }

    /// The text Save stores: the article on screen, else the page's own (its listen blocks when
    /// it has none built).
    private var textToSave: ReaderArticle? {
        if let readerArticle { return readerArticle.document.isEmpty ? nil : readerArticle }
        guard let article, !article.isLink else { return nil }
        var readerArticle = ReaderArticle(article: article)
        if readerArticle.document.isEmpty { readerArticle.document = article.listenDocument() }
        return readerArticle
    }
}

extension LibraryStore {
    /// The page for `key` and `canonicalURL` by `article(key:canonicalURL:)`, when it is saved in
    /// the Library.
    func savedArticle(key: UUID, canonicalURL: String?) -> Article? {
        guard let article = article(key: key, canonicalURL: canonicalURL), article.isSavedToLibrary else { return nil }
        return article
    }
}

/// The Library page a screen's page is, live: its address first, then its key, the rule
/// `LibraryStore.article(key:canonicalURL:)` follows. Two one-row queries, so the screen follows a
/// save, a remove or a ☆ made anywhere, and reads nothing else.
struct ArticleLookup<Content: View>: View {
    @Query private var byAddress: [Article]
    @Query private var byKey: [Article]
    private let content: (Article?) -> Content

    /// `key` nil or `canonicalURL` nil: that half finds nothing (no page has an empty address or
    /// the nil UUID).
    init(key: UUID?, canonicalURL: String?, @ViewBuilder content: @escaping (Article?) -> Content) {
        _byAddress = Query(Self.byAddress(canonicalURL ?? ""))
        _byKey = Query(LibraryQueries.article(key: key ?? Self.noKey))
        self.content = content
    }

    var body: some View {
        content(Self.article(byAddress: byAddress.first, byKey: byKey.first))
    }

    private static var noKey: UUID { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) }

    /// The oldest page for the address, as `LibraryStore.article(canonicalURL:)` reads it.
    static func byAddress(_ canonicalURL: String) -> FetchDescriptor<Article> {
        var descriptor = LibraryQueries.articles(canonicalURL: canonicalURL)
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func article(byAddress: Article?, byKey: Article?) -> Article? {
        byAddress ?? byKey
    }
}
