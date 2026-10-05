import SwiftUI

/// What the Reader sheet sits over, named by its back pill ("‹ Browser", "‹ Library").
enum ReaderOrigin: Equatable {
    /// Over the browser: 📄, ⋯ → Reader, a start-page row.
    case browser
    /// Over the Library: a page row, a Continue card, the Favorites sheet opened there.
    case library

    /// The back pill's title.
    var backTitle: String {
        switch self {
        case .browser: "Browser"
        case .library: "Library"
        }
    }
}

/// The Reader sheet: a page shown for reading over the surface that opened it.
struct ReaderSheetState: Equatable {
    var article: ReaderArticle
    var origin: ReaderOrigin
    /// This showing of the sheet. Its close reports it (`readerDidClose`), so a close that lands
    /// late can't remove a Reader opened since.
    let presentation = UUID()
}

/// The shell's sheets. One at a time, shown by the shell's single `.sheet(item:)`.
enum ShellSheet: Identifiable, Equatable {
    /// The Favorites folder screen (pushed into `folder`, one of its subfolders, when given): its
    /// links open in the browser, its saved pages in the Reader.
    case favorites(folder: UUID? = nil)
    case history
    case voiceSettings
    case share(URL)
    /// The Move tree: Move, *Save to Library…*, 🔖's *Save to Folder…*, *Change Folder*.
    case moveTo(MoveRequest)

    var id: String {
        switch self {
        case .favorites(let folder): "favorites-\(folder?.uuidString ?? "")"
        case .history: "history"
        case .voiceSettings: "voiceSettings"
        case .share(let url): "share-\(url.absoluteString)"
        case .moveTo(let request): "moveTo-\(request.id)"
        }
    }

    /// History lists browser destinations, so it belongs to the browser: presenting it from the
    /// library leaves the library first. The others show over whatever is on screen.
    var belongsToBrowser: Bool {
        switch self {
        case .history: true
        case .favorites, .voiceSettings, .share, .moveTo: false
        }
    }
}

/// One use of the Move tree: what it is for, where the item is now, and what picking a place
/// does. `onPick` gets the chosen folder, or nil for the top level ("Library (no folder)"), and
/// returns false when that couldn't be saved (its toast says so): the tree stays up, so another
/// place can be picked or the tree cancelled. True closes it.
struct MoveRequest: Identifiable, Equatable {
    enum Place: Equatable {
        case topLevel
        case folder(UUID)
    }

    let id = UUID()
    /// "Move to…", "Save to…".
    var title: String
    /// Marked ✓.
    var current: Place?
    /// Folders being moved: they and everything inside them can't be picked (no cycles).
    var moving: Set<UUID> = []
    let onPick: (Folder?) -> Bool

    static func == (a: MoveRequest, b: MoveRequest) -> Bool { a.id == b.id }
}

/// A short message over the bottom chrome, with an optional action ("Added to Favorites ·
/// Change Folder").
struct ShellToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var systemImage: String?
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (a: ShellToast, b: ShellToast) -> Bool { a.id == b.id }
}

/// A question with one confirming choice and Cancel ("Move it to Favorites?").
struct ShellPrompt: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String?
    var confirmTitle: String
    let confirm: () -> Void

    static func == (a: ShellPrompt, b: ShellPrompt) -> Bool { a.id == b.id }
}

/// Page extraction in progress (spinner on the address-bar reader icon, or on ⋯ for Save).
enum BusyAction: Equatable {
    case reader
    case save
}

/// What you see: one surface (the browser or the Library at a folder), the Reader sheet over it,
/// Now Playing over everything, at most one other sheet, at most one ⋯ menu. The surface and the
/// Library's path are remembered, and the app reopens on them (decision D10). What you hear belongs to the
/// playback session; the shell only asks it (`isHearing`), so opening the Reader of the page you
/// hear opens Now Playing instead.
///
/// Every way of leaving a surface goes through here, so invalid combinations (a Reader of the page
/// that is playing, the library's Reader left behind on the browser) can't be represented.
@MainActor
@Observable
final class ShellState {
    enum Surface {
        /// The web page or the start page.
        case browse
        /// The Library, at `libraryPath`.
        case library
    }

    private(set) var surface: Surface = .browse {
        didSet { remember() }
    }
    /// The Library's pushed screens, nearest the home first (`[.folder(Fiction), .folder(Short
    /// stories)]`). Kept while the browser is up, so 🌐 and back return to the same folder.
    var libraryPath: [LibraryRoute] = [] {
        didSet { remember() }
    }
    /// The Reader sheet (nil = closed). Removed by `readerDidClose` once its sheet has gone.
    private(set) var reader: ReaderSheetState?
    /// This showing of Now Playing (nil = down), over the surface and the Reader sheet. It shows
    /// what you hear, so it holds no article of its own. Its close reports the showing it closed
    /// (`nowPlayingDidClose`), so a close that lands late can't take down a newer one.
    private(set) var nowPlayingPresentation: UUID?
    var isNowPlayingPresented: Bool { nowPlayingPresentation != nil }
    /// Where Now Playing's text opens: the Reader's scroll position (its reading page's
    /// `handOver`) when its Listen turned it into Now Playing (it appears in place, without
    /// rising). nil = it rises and finds the audio.
    private(set) var nowPlayingOpensAt: ReadingHandOver?
    var sheet: ShellSheet?
    /// The open ⋯ menu (nil = closed), rendered by the shell's one `MorphMenuOverlay`.
    var menu: MenuContext?
    /// A short message over the bottom chrome of the surface on screen.
    private(set) var toast: ShellToast?
    /// A question waiting for an answer.
    var prompt: ShellPrompt?
    /// Global frame of the ⋯ button the open menu grows from.
    private(set) var menuAnchor: CGRect = .zero
    var busy: BusyAction?
    let web = WebViewStore()
    /// The browser's address field. Idle, its text is the page's address.
    let addressSearch = SearchSession()
    /// Whether a target is what you hear (the playback session answers).
    private let isHearing: (ListenTarget) -> Bool

    /// Where the surface is remembered (nil: not remembered, as in unit tests).
    private let memory: SurfaceMemoryStore?
    /// The browser page to reload at launch (`restoreAtLaunch`).
    private var pendingBrowserURL: URL?

    /// `restores`: open on the remembered surface, or the Library when there is none (a fresh
    /// install). Otherwise the browser's start page.
    init(isHearing: @escaping (ListenTarget) -> Bool = { _ in false }, memory: SurfaceMemoryStore? = nil,
         restores: Bool = false) {
        self.isHearing = isHearing
        self.memory = memory
        guard restores, let memory else { return }
        if let last = memory.load() {
            surface = last.base == .library ? .library : .browse
            libraryPath = last.libraryPath
            pendingBrowserURL = last.browserURL.flatMap(URL.init(string:))
        } else {
            surface = .library
        }
    }

    // MARK: - Surface queries

    /// The Reader sheet's article, when it is open.
    var readerArticle: ReaderArticle? { reader?.article }

    var isBrowsing: Bool {
        if case .browse = surface { true } else { false }
    }

    var isInLibrary: Bool {
        if case .library = surface { true } else { false }
    }

    // MARK: - The Reader sheet

    /// The Reader sheet on `article`, over the surface on screen. The page you hear opens as Now
    /// Playing instead: the Reader never shows what is playing.
    func openReader(_ article: ReaderArticle) {
        if isHearing(.page(article.id)) || isHearing(.webPage(canonicalURL: article.canonicalURL)) {
            showNowPlaying()
            return
        }
        reader = ReaderSheetState(article: article, origin: isInLibrary ? .library : .browser)
    }

    /// Updates the Reader sheet's article in place (favicon arrived, listen blocks built, Save
    /// rekeyed it), if that article is still the one shown.
    func updateReader(id: UUID, _ change: (inout ReaderArticle) -> Void) {
        guard var state = reader, state.article.id == id else { return }
        change(&state.article)
        reader = state
    }

    /// Closes the Reader sheet at once (its ⋯ → Saved from the Library). Playback keeps going.
    func closeReader() {
        reader = nil
    }

    /// The Reader sheet shown as `presentation` has gone (its back pill, the grabber's pull down,
    /// after its own close animation). A Reader opened since stays.
    func readerDidClose(_ presentation: UUID) {
        guard reader?.presentation == presentation else { return }
        reader = nil
    }

    // MARK: - Now Playing

    /// The bar's tap and swipe up, crash resume. Over everything; the surface and its state (the
    /// page, the Library) stay as they are underneath. A Reader sheet of the page you hear closes,
    /// so the two never show the same page.
    func showNowPlaying() {
        endAddressSearch()
        if let article = reader?.article,
           isHearing(.page(article.id)) || isHearing(.webPage(canonicalURL: article.canonicalURL)) {
            reader = nil
        }
        nowPlayingOpensAt = nil
        presentNowPlaying()
    }

    /// Listen in the Reader (decision D2): the Reader turns into Now Playing where it was
    /// (`handOver`; nil when its page wasn't up, and Now Playing rises as from the bar).
    func turnReaderIntoNowPlaying(handOver: ReadingHandOver?) {
        reader = nil
        nowPlayingOpensAt = handOver
        presentNowPlaying()
    }

    /// Already up, it stays the same showing.
    private func presentNowPlaying() {
        if nowPlayingPresentation == nil { nowPlayingPresentation = UUID() }
    }

    /// Takes Now Playing down at once, back to the surface underneath.
    func hideNowPlaying() {
        nowPlayingPresentation = nil
        nowPlayingOpensAt = nil
    }

    /// ⌄ or the pull down, after the close animation of the showing `presentation`. A Now Playing
    /// shown since stays.
    func nowPlayingDidClose(_ presentation: UUID) {
        guard nowPlayingPresentation == presentation else { return }
        hideNowPlaying()
    }

    // MARK: - Remembering the surface

    /// At launch, once the library is open: the path keeps the folders that still exist (up to the
    /// first that doesn't), and the browser reloads its last page: now when it is showing, or the
    /// first time you go there from the Library (`leaveLibrary`).
    func restoreAtLaunch(folderExists: (UUID) -> Bool) {
        pruneLibraryPath(keeping: folderExists)
        if isBrowsing, let url = pendingBrowserURL {
            pendingBrowserURL = nil
            navigate(to: url)
        }
    }

    /// The browser's page changed: its address field, and the page to reopen on.
    func browserPageChanged() {
        syncAddressField()
        remember()
    }

    private func remember() {
        guard let memory else { return }
        memory.save(SurfaceMemory(base: isInLibrary ? .library : .browse, libraryPath: libraryPath,
                                  browserURL: (web.currentURL ?? pendingBrowserURL)?.absoluteString))
    }

    // MARK: - Library navigation

    /// The Library's path up to the first folder that no longer exists (it was deleted).
    func pruneLibraryPath(keeping folderExists: (UUID) -> Bool) {
        guard let gone = libraryPath.firstIndex(where: { route in
            if case .folder(let id) = route { return !folderExists(id) }
            return false
        }) else { return }
        libraryPath = Array(libraryPath[..<gone])
    }

    /// "Playing from", a search result, a Continue card: the Library at `folder` (pushed under
    /// the folders above it).
    func showLibrary(at path: [LibraryRoute]) {
        openLibrary()
        libraryPath = path
    }

    // MARK: - Surfaces

    func openLibrary() {
        endAddressSearch()
        reader = nil
        hideNowPlaying()
        surface = .library
    }

    /// Back to the browser as it was: the page (or start page) under the library is untouched. A
    /// Reader opened from the library goes with it.
    func leaveLibrary() {
        guard isInLibrary else { return }
        if reader?.origin == .library { reader = nil }
        surface = .browse
        // Reopened on the Library: the browser's last page loads the first time you go there.
        if let url = pendingBrowserURL, web.currentURL == nil {
            pendingBrowserURL = nil
            navigate(to: url)
        }
    }

    /// The browser, with nothing over it: closes the Reader and Now Playing, leaves the library.
    func showBrowser() {
        reader = nil
        hideNowPlaying()
        leaveLibrary()
    }

    // MARK: - Pages

    /// Shows `url` in the browser: ends the address search, leaves the reader or library, loads.
    /// Every way of going to a page (submitted address, bookmark, history, Website) ends here.
    func navigate(to url: URL) {
        addressSearch.end(showing: Self.addressText(for: url))
        showBrowser()
        web.load(url)
    }

    /// The article's own page: revealed as it is when it's the page already loaded (no reload,
    /// scroll kept), else loaded. Audio keeps playing.
    func openWebsite(_ url: URL) {
        if let current = web.currentURL, current.isSamePage(as: url) {
            endAddressSearch()
            showBrowser()
        } else {
            navigate(to: url)
        }
    }

    /// ⋯ → New search: the start page, with an empty address field.
    func showStartPage() {
        addressSearch.end(showing: "")
        web.showStartPage()
    }

    // MARK: - Address field

    /// ✕, or leaving the browser: ends the search and puts the page's address back.
    func endAddressSearch() {
        addressSearch.end(showing: Self.addressText(for: web.currentURL))
    }

    /// The page changed: show its address, unless the user is searching.
    func syncAddressField() {
        guard !addressSearch.isActive else { return }
        addressSearch.text = Self.addressText(for: web.currentURL)
    }

    /// The idle address field's text, like Safari: host and path (no scheme, no lone "/"); empty
    /// on the start page.
    nonisolated static func addressText(for url: URL?) -> String {
        guard let url else { return "" }
        guard let host = url.host else { return url.absoluteString }
        return host + (url.path == "/" ? "" : url.path)
    }

    // MARK: - Menu and sheets

    func openMenu(_ context: MenuContext, from anchor: CGRect) {
        menuAnchor = anchor
        menu = context
    }

    func present(_ sheet: ShellSheet) {
        if sheet.belongsToBrowser { leaveLibrary() }
        self.sheet = sheet
    }

    // MARK: - Toasts and prompts

    func showToast(_ toast: ShellToast) {
        self.toast = toast
    }

    /// Runs a change that can fail, such as a library edit (`LibraryStore` rolls back a save that
    /// fails, so nothing changed): its result, or nil once a toast has said `failure`.
    @discardableResult
    func attempt<Result>(_ failure: String, _ change: () throws -> Result) -> Result? {
        do {
            return try change()
        } catch {
            showToast(ShellToast(message: failure, systemImage: "exclamationmark.triangle"))
            return nil
        }
    }

    /// The toast shown as `id` has had its time (or its action ran). A newer one stays.
    func dismissToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    // MARK: - Library pages

    /// A library page in the Reader sheet (a row, a Continue card, a favorite): shown as soon as
    /// the page is read; older pages build their listen blocks afterwards.
    func openSaved(_ id: UUID, in library: LibraryStore) {
        Task {
            var shown = false
            await ReaderArticle.loadSaved(id: id, in: library) { article in
                if shown {
                    updateReader(id: article.id) { $0 = article }
                } else {
                    shown = true
                    openReader(article)
                }
            }
        }
    }
}
