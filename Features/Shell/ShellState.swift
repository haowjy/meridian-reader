import SwiftUI
import SwiftData

/// Where a reader was opened from. Decides what "back" means; independent of how the reader is
/// presented (`ReaderPresentation`).
enum ReaderOrigin: Equatable {
    /// Extracted from the page loaded in the browser (address-bar reader icon, ⋯ → Reader).
    case page(URL)
    /// A saved article opened from the library list.
    case library
    /// Opened on its own: a start-page row, Continue listening, the mini player, crash resume.
    case standalone
}

/// How the reader screen is shown.
enum ReaderPresentation: Equatable {
    /// Full-screen over the browser, closed with ✕ or a pull-down on its top row.
    case overlay
    /// Pushed inside the library's navigation stack, closed with ‹ or the edge swipe.
    case pushed
}

/// The shell's sheets. One at a time, shown by the shell's single `.sheet(item:)`.
enum ShellSheet: Identifiable, Equatable {
    case bookmarks
    case history
    case voiceSettings
    case share(URL)

    var id: String {
        switch self {
        case .bookmarks: "bookmarks"
        case .history: "history"
        case .voiceSettings: "voiceSettings"
        case .share(let url): "share-\(url.absoluteString)"
        }
    }

    /// Bookmarks and History list browser destinations, so they belong to the browser: presenting
    /// one from the library leaves the library first. The others show over whatever is on screen.
    var belongsToBrowser: Bool {
        switch self {
        case .bookmarks, .history: true
        case .voiceSettings, .share: false
        }
    }
}

/// Page extraction in progress (spinner on the address-bar reader icon, or on ⋯ for Save).
enum BusyAction: Equatable {
    case reader
    case save
}

/// The app's presentation state: one surface (browser, reader or library), at most one sheet.
/// Every way of leaving a surface goes through here, so invalid combinations (the library over a
/// reader, a sheet waiting for the library to close) can't be represented.
@MainActor
@Observable
final class ShellState {
    enum Surface {
        /// The web page or the start page.
        case browse
        /// The ✕ reader over the browser.
        case reader(ReaderArticle, origin: ReaderOrigin)
        /// The library list; `path` is its navigation stack (pushed ‹ readers).
        case library(path: [UUID])
    }

    private(set) var surface: Surface = .browse
    var sheet: ShellSheet?
    var busy: BusyAction?
    let web = WebViewStore()
    /// The unsaved article the mini player reopens: the reader article that became the active
    /// listening session. Saved articles reopen from the store instead.
    private(set) var nowPlayingArticle: ReaderArticle?

    static let readerFade = Animation.easeInOut(duration: 0.2)

    // MARK: - Surface queries

    /// The ✕ reader's article, when it is the surface.
    var readerArticle: ReaderArticle? {
        if case .reader(let article, _) = surface { article } else { nil }
    }

    var isBrowsing: Bool {
        if case .browse = surface { true } else { false }
    }

    var isInLibrary: Bool {
        if case .library = surface { true } else { false }
    }

    /// The library's navigation stack. Writes are ignored once the library is gone, so its
    /// `NavigationStack` tearing down can't bring it back.
    var libraryPath: [UUID] {
        get { if case .library(let path) = surface { path } else { [] } }
        set { if case .library = surface { surface = .library(path: newValue) } }
    }

    // MARK: - Surfaces

    func showReader(_ article: ReaderArticle, origin: ReaderOrigin) {
        withAnimation(Self.readerFade) { surface = .reader(article, origin: origin) }
    }

    /// Updates the ✕ reader's article in place (favicon arrived, listen blocks built, Save
    /// rekeyed it), if that article is still the one shown.
    func updateReader(id: UUID, _ change: (inout ReaderArticle) -> Void) {
        guard case .reader(var article, let origin) = surface, article.id == id else { return }
        change(&article)
        surface = .reader(article, origin: origin)
    }

    /// ✕ / pull-down. Playback keeps going; the mini player takes over.
    func hideReader() {
        guard case .reader = surface else { return }
        withAnimation(Self.readerFade) { surface = .browse }
    }

    func openLibrary() {
        surface = .library(path: [])
    }

    /// Back to the browser as it was: the page (or start page) under the library is untouched.
    func leaveLibrary() {
        guard isInLibrary else { return }
        surface = .browse
    }

    /// Leaves the reader or the library for the browser.
    func showBrowser() {
        switch surface {
        case .browse: break
        case .reader: hideReader()
        case .library: leaveLibrary()
        }
    }

    // MARK: - Pages

    /// Shows `url` in the browser, leaving the reader or library.
    func navigate(to url: URL) {
        showBrowser()
        web.load(url)
    }

    /// The article's own page: revealed as it is when it's the page already loaded (no reload,
    /// scroll kept), else loaded. Audio keeps playing.
    func openWebsite(_ url: URL) {
        if let current = web.currentURL, current.isSamePage(as: url) {
            showBrowser()
        } else {
            navigate(to: url)
        }
    }

    // MARK: - Sheets

    func present(_ sheet: ShellSheet) {
        if sheet.belongsToBrowser { leaveLibrary() }
        self.sheet = sheet
    }

    // MARK: - Saved articles

    /// A saved article in the ✕ reader (start page row, mini player, crash resume). Shows it as
    /// soon as the row is read; older saves build their listen blocks afterwards.
    func openSaved(_ id: UUID, in context: ModelContext) {
        Task {
            var shown = false
            await ReaderArticle.loadSaved(id: id, in: context) { article in
                if shown {
                    updateReader(id: article.id) { $0 = article }
                } else {
                    shown = true
                    showReader(article, origin: .standalone)
                }
            }
        }
    }

    /// Mini player tap: the reader for whatever is loaded for listening.
    func openNowPlaying(_ id: UUID, in context: ModelContext) {
        if ArticleLibrary.savedArticle(id: id, in: context) != nil {
            openSaved(id, in: context)
        } else if let article = nowPlayingArticle, article.id == id {
            showReader(article, origin: .standalone)
        }
    }

    /// The listening session changed: remember the reader article it belongs to, so the mini
    /// player can bring an unsaved article back.
    func noteActiveSession(_ id: UUID?) {
        guard let id, let article = readerArticle, article.id == id else { return }
        nowPlayingArticle = article
    }
}
