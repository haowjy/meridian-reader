import SwiftUI

/// What the Reader sheet sits over, named by its back pill ("‹ Browser", "‹ Library").
enum ReaderOrigin: Equatable {
    /// Over the browser: 📄, ⋯ → Reader, a start-page row.
    case browser
    /// Over the Library: a page row.
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

/// The shell's sheets. One at a time, shown by the shell's single `.sheet(item:)`, or its
/// `.fullScreenCover(item:)` for one that covers the screen (`coversTheScreen`).
enum ShellSheet: Identifiable, Equatable {
    case history
    case settings
    case share(URL)
    /// The Move tree: *Move to…*, and *Save to Folder…* (a menu's row, 🔖 held).
    case moveTo(MoveRequest)
    /// A book being imported: its progress, *Add to*, and D13's question.
    case importBook(BookImportFlow)
    /// ⋯ › Downloads: what is downloading and downloaded (decision D16).
    case downloads
    /// *Edit Details* for a folder, book or series: its name, author and cover.
    case folderDetails(UUID)
    /// ⋯ → *Follow…*: a story's table of contents, reviewed, into a folder of chapters.
    case follow(FollowFlow)
    /// A followed story's status line: its checks, *Check Now*, *Unfollow*.
    case following(UUID)
    /// Developer options: the listen debug panel (Settings › Developer › Listen Debug Panel, a
    /// long-press on ▶ / ⏸). The one sheet that shows over another (`showsOverASheet`).
    case listenDebug

    var id: String {
        switch self {
        case .history: "history"
        case .settings: "settings"
        case .share(let url): "share-\(url.absoluteString)"
        case .moveTo(let request): "moveTo-\(request.id)"
        case .importBook(let flow): "importBook-\(flow.id)"
        case .downloads: "downloads"
        case .folderDetails(let id): "folderDetails-\(id.uuidString)"
        case .follow(let flow): "follow-\(flow.id)"
        case .following(let id): "following-\(id.uuidString)"
        case .listenDebug: "listenDebug"
        }
    }

    /// Follow covers the screen rather than rising as a card: its chapter previews are the app's
    /// own sheet (`Sheet`), whose pull down a card's own pull would take.
    var coversTheScreen: Bool {
        if case .follow = self { return true }
        return false
    }

    /// Presented while another sheet is up, it shows over that one and closes back to it: the
    /// listen debug panel opened from Settings.
    var showsOverASheet: Bool { self == .listenDebug }

    /// History lists browser destinations, so it belongs to the browser: presenting it from the
    /// library leaves the library first. The others show over whatever is on screen.
    var belongsToBrowser: Bool {
        switch self {
        case .history: true
        case .settings, .share, .moveTo, .importBook, .downloads, .folderDetails, .follow, .following, .listenDebug: false
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
    /// The sheet's title: "Move to", "Save to Folder" (the row that opened it, `Verbs.title`).
    var title: String
    /// Marked ✓.
    var current: Place?
    /// Folders being moved: they and everything inside them can't be picked (no cycles).
    var moving: Set<UUID> = []
    let onPick: (Folder?) -> Bool

    static func == (a: MoveRequest, b: MoveRequest) -> Bool { a.id == b.id }
}

/// A short message over the bottom chrome ("Added to Favorites"), with an optional action button.
struct ShellToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var systemImage: String?
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (a: ShellToast, b: ShellToast) -> Bool { a.id == b.id }
}

/// Page extraction in progress (spinner on the address-bar reader icon, or on ⋯ for Save).
enum BusyAction: Equatable {
    case reader
    case save
}

/// What you see: one surface (the browser or the Library at a folder), the Reader sheet over it,
/// Now Playing over everything, at most one other sheet, at most one ⋯ menu. The surface, the
/// Library's path and its home's tab are remembered, and the app reopens on them (decision D10). What you hear belongs to the
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
    /// The Library home's tab (`LibraryHomeTab`). Its picker sets it; going to a place in the
    /// Library shows Everything (`showLibrary(at:)`), ⋯ → Favorites shows Favorites
    /// (`showFavorites`), and 📚 keeps it. Remembered with the surface.
    var homeTab = LibraryHomeTab.everything {
        didSet { memory?.saveHomeTab(homeTab) }
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
    var sheet: ShellSheet? {
        didSet { if sheet == nil { overSheet = nil } }
    }
    /// A sheet over `sheet` (`ShellSheet.showsOverASheet`); it goes with it.
    var overSheet: ShellSheet?
    /// *Import Book…*'s Files picker is up (`pickBook(into:)`).
    var isPickingBook = false
    /// Where the picked book goes (nil: the Library's top level).
    private(set) var bookPickDestination: UUID?
    /// The open ⋯ menu (nil = closed), rendered by the shell's one `MorphMenuOverlay`.
    var menu: MenuContext?
    /// A short message over the bottom chrome of the surface on screen.
    private(set) var toast: ShellToast?
    /// Global frame of the ⋯ button the open menu grows from.
    private(set) var menuAnchor: CGRect = .zero
    var busy: BusyAction?
    let web = WebViewStore()
    /// The browser's address field. Idle, its text is the page's address.
    let addressSearch = SearchSession()
    /// The Library's search field, in the band (decision D22): its text filters the Library home.
    let librarySearch = SearchSession()
    /// Whether a target is what you hear (the playback session answers).
    private let isHearing: (ListenTarget) -> Bool

    /// Where the surface is remembered (nil: not remembered, as in unit tests).
    private let memory: SurfaceMemoryStore?
    /// The browser page to reload at launch (`restoreAtLaunch`).
    private var pendingBrowserURL: URL?

    /// `restores`: open on the remembered surface and Library tab, or the Library when there is
    /// none (a fresh install). Otherwise the browser's start page, the Library on Everything.
    init(isHearing: @escaping (ListenTarget) -> Bool = { _ in false }, memory: SurfaceMemoryStore? = nil,
         restores: Bool = false) {
        self.isHearing = isHearing
        self.memory = memory
        guard restores, let memory else { return }
        homeTab = memory.loadHomeTab()
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
        if isHearingPage(of: article) {
            showNowPlaying()
            return
        }
        reader = ReaderSheetState(article: article, origin: isInLibrary ? .library : .browser)
    }

    /// Whether `article`'s page is what you hear: by key, or a web page by its address.
    private func isHearingPage(of article: ReaderArticle) -> Bool {
        isHearing(.page(article.id)) || article.origin.canonicalURL.map { isHearing(.webPage(canonicalURL: $0)) } == true
    }

    /// Updates the Reader sheet's article in place (favicon arrived, listen blocks built, Save
    /// rekeyed it), if that article is still the one shown.
    func updateReader(id: UUID, _ change: (inout ReaderArticle) -> Void) {
        guard var state = reader, state.article.id == id else { return }
        change(&state.article)
        reader = state
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
        if let article = reader?.article, isHearingPage(of: article) {
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

    /// A place in the Library (*Go to* a folder or the Library, a favorite folder's tile, an
    /// imported book): the Library at `path` (a folder pushed under the folders above it, or
    /// `[]` for the home), on Everything, where every place shows.
    func showLibrary(at path: [LibraryRoute]) {
        openLibrary()
        libraryPath = path
        homeTab = .everything
    }

    /// ⋯ → Favorites, the start page's *Show All*: the Library home on its Favorites tab.
    func showFavorites() {
        openLibrary()
        libraryPath = []
        homeTab = .favorites
    }

    // MARK: - Surfaces

    /// 📚: the Library as it was left, its place and its tab.
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
        librarySearch.end(showing: "")
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

    /// The Library's ✕: ends its search and clears the filter.
    func endLibrarySearch() {
        librarySearch.end(showing: "")
    }

    /// The Library's search began: it filters the home, so a folder screen gives way to it.
    func librarySearchBegan() {
        if !libraryPath.isEmpty { libraryPath = [] }
    }

    /// The Library's ‹: up one level (nothing at the home).
    func libraryBack() {
        if !libraryPath.isEmpty { libraryPath.removeLast() }
    }

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
        if sheet.showsOverASheet, let under = self.sheet, under != sheet {
            overSheet = sheet
        } else {
            self.sheet = sheet
        }
    }

    /// The import sheet's flow, while it is the sheet up.
    var importFlow: BookImportFlow? {
        if case .importBook(let flow) = sheet { flow } else { nil }
    }

    /// Closes the import sheet if it shows `flow`; true if it did. Another flow's sheet (or
    /// another sheet) that came up since stays: a flow only closes its own.
    @discardableResult
    func closeImport(_ flow: BookImportFlow) -> Bool {
        guard importFlow === flow else { return false }
        sheet = nil
        return true
    }

    /// *Import Book…*: the Files picker, for a book going into `destination`.
    func pickBook(into destination: UUID?) {
        bookPickDestination = destination
        isPickingBook = true
    }

    // MARK: - Toasts

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
            showToast(ShellToast(message: failure, systemImage: Icons.warning))
            return nil
        }
    }

    /// The toast shown as `id` has had its time (or its action ran). A newer one stays.
    func dismissToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    /// Each place showing the toast shown as `id` waits `duration`, then dismisses it. A wait
    /// that is cancelled (that place went away, such as a sheet closing just as the toast came
    /// up) leaves it showing for the others, which wait their own time.
    func expireToast(_ id: UUID, after duration: Duration) async {
        guard (try? await Task.sleep(for: duration)) != nil else { return }
        withAnimation(Motion.snappy) { dismissToast(id) }
    }

    // MARK: - Library pages

    /// A library page in the Reader sheet (a row, a favorite): shown as soon as
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
