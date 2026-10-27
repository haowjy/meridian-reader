import SwiftUI

/// What the Reader was opened over. Regular width names it on the sheet's back pill ("‹ Browser",
/// "‹ Library"); leaving the Library takes a Reader opened over it along.
enum ReaderOrigin: Equatable {
    /// Over the browser: 📄, ⋯ → Reader, a start-page row.
    case browser
    /// Over the Library: a page row.
    case library

    /// The back pill's title.
    var backTitle: String {
        switch self {
        case .browser: Verbs.browser
        case .library: Verbs.library
        }
    }
}

/// The Reader: a page shown for reading. On compact width it is a destination in the chrome's pill,
/// in place over the surface that opened it; on regular width a sheet over it.
struct ReaderSheetState: Equatable {
    var article: ReaderArticle
    var origin: ReaderOrigin
    /// This showing of the Reader. A sheet's close reports it (`readerDidClose`), so a close that
    /// lands late can't remove a Reader opened since.
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
    /// ⋯ › Prepared audio: what is preparing and prepared (decision D16).
    case preparedAudio
    /// *Edit Details* for a folder, book or series: its name, author and cover.
    case folderDetails(UUID)
    /// *Voice: Heart* in an article's or a book's menu: its voice picker (C138).
    case voice(VoiceTarget)
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
        case .preparedAudio: "downloads"
        case .folderDetails(let id): "folderDetails-\(id.uuidString)"
        case .voice(let target): "voice-\(target.id)"
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

    // Every sheet shows over whatever is on screen: History from the Library keeps the Library
    // under it (C130); opening a page from it goes to the browser as any page does.
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

/// What you see: one surface (the browser or the Library at a folder), the Reader over it,
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

    /// The compact bottom chrome's presence (collapsed to one row, the Reader's full screen) and the
    /// one scroll controller the Library, the Browser and the Reader feed.
    let chromeScroll = ChromeScroll()

    private(set) var surface: Surface = .browse {
        didSet { remember() }
    }
    /// The Library's pushed screens, nearest the home first (`[.folder(Fiction), .folder(Short
    /// stories)]`). Kept while the browser is up, so 🌐 and back return to the same folder.
    var libraryPath: [LibraryRoute] = [] {
        didSet {
            remember()
            if let folder = librarySearchFolder, !libraryPath.contains(.folder(folder)) { endLibrarySearch() }
        }
    }
    /// The folder the Library's search searches: the folder screen on top when it began (nil:
    /// the home, which searches its tab). It ends once that folder leaves the path.
    private(set) var librarySearchFolder: UUID?
    /// The Library home's tab (`LibraryHomeTab`). Its picker sets it; going to a place in the
    /// Library shows Everything (`showLibrary(at:)`), ⋯ → Favorites shows Favorites
    /// (`showFavorites`), and 📚 keeps it. Remembered with the surface.
    var homeTab = LibraryHomeTab.everything {
        didSet { memory?.saveHomeTab(homeTab) }
    }
    /// The Reader (nil = closed). A sheet's close ends it through `readerDidClose` once it has gone;
    /// in place, leaving it is choosing another destination.
    private(set) var reader: ReaderSheetState?
    /// The Browser's page as the Reader draws it, in place of the page (nil = the page itself).
    /// The address pill's reader icon toggles it; it is the page's own, so it ends when the page changes.
    private(set) var pageReader: ReaderArticle?
    /// A Library page read in place (Library *Read*): its text replaces the Library's content, like the
    /// Browser's reader mode, under the same chrome with the Library segment lit. Nothing plays until
    /// Listen (which raises Now Playing); the destination does not change; ‹ (or the edge swipe)
    /// puts the Library back as it was.
    private(set) var libraryReader: ReaderArticle?
    /// Compact width reads in place (`libraryReader`, `pageReader`); regular width keeps the Reader sheet.
    var readsInPlace = false
    /// The text appearance panel of the Browser's in-place reader, opened from ⋯ (the Library's has Aa on its capsule).
    var readerAppearanceOpen = false
    /// Counts the endings of an in-place reader (`closePageReader`): an extraction that began
    /// under an earlier count opens nothing (the user left, or the page moved on, meanwhile).
    private(set) var pageReaderEpoch = 0
    /// This showing of Now Playing (nil = down), over the surface and the Reader. It shows
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
    /// Regular-width sidebar collapsed for focus reading / full-bleed Browse (iPad). Compact ignores it.
    var sidebarCollapsed = false
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

    /// The Reader's article, when it is open.
    var readerArticle: ReaderArticle? { reader?.article }

    var isBrowsing: Bool {
        if case .browse = surface { true } else { false }
    }

    var isInLibrary: Bool {
        if case .library = surface { true } else { false }
    }

    // MARK: - The chrome's destination

    /// The Reader is lit while the Reader or Now Playing is up; otherwise the surface under.
    var chromeDestination: ChromeDestination {
        if reader != nil || isNowPlayingPresented { .reader } else if isInLibrary { .library } else { .browse }
    }

    /// The place that LAUNCHED the listening: where Listen / Play was pressed (a Library row, folder or book
    /// page, with its tab and any Library Read in place; or the Browser's page, in reader mode when it was
    /// reading). Set when a direct Listen / Play action starts or switches the audio (`noteLaunch`; a new
    /// launch replaces it) and never by switching destinations: Library → Browser → Listen still goes ‹ back to
    /// the Library. ‹ and the card's title block both go to it and leave it, so repeated visits work.
    /// Nil on a cold launch straight to Listen (crash resume): no ‹.
    private(set) var listenLaunch: ListenLaunch?

    /// Whether Listen's floating ‹ shows: on Listen, with a launch record.
    var listenBackTarget: ListenLaunch? { chromeDestination == .reader ? listenLaunch : nil }

    /// A direct Listen / Play action starts or switches the audio (`SpeechController.onLaunch`): records the
    /// place it was pressed in. Not from Listen itself (a chapter picked there stays launched from the
    /// place before).
    func noteLaunch() {
        guard chromeDestination != .reader else { return }
        if isInLibrary {
            listenLaunch = ListenLaunch(place: .library(path: libraryPath, tab: homeTab, reading: libraryReader))
        } else {
            let url = web.currentURL ?? pendingBrowserURL
            listenLaunch = url.map { ListenLaunch(place: .browser(url: $0, reading: pageReader)) }
        }
    }

    /// Listen's ‹ and the card's title block: takes Listen down and goes to the launching place, its state
    /// as it was left (the Library's path, tab and Read in place; the Browser's page, in reader mode if it
    /// was reading). The record stays.
    func backFromListen() {
        guard let launch = listenBackTarget else { return }
        endAddressSearch()
        reader = nil
        hideNowPlaying()
        switch launch.place {
        case .library(let path, let tab, let reading):
            openLibrary()
            libraryPath = path
            homeTab = tab
            if let reading { openLibraryReader(reading) } else { closeLibraryReader() }
        case .browser(let url, let reading):
            if let current = web.currentURL, current.isSamePage(as: url) {
                showBrowser()
                if let reading, readsInPlace { openPageReader(reading, requestedAt: pageReaderEpoch) } else if reading == nil { closePageReader() }
            } else {
                navigate(to: url)
                readerLeftByBack = nil
                readerToReenter = reading == nil ? nil : url
            }
        }
    }

    /// A tap on a segment of the chrome's pill. The lit segment is where you already are. The
    /// Reader segment, until the Reader is a screen of its own: what is playing opens as Now
    /// Playing, else `resume` opens the page played last in the Reader; with neither, a note.
    func select(_ target: ChromeDestination, isPlaying: Bool, resume: (() -> Void)?) {
        guard target != chromeDestination else { return }
        switch target {
        case .library: openLibrary()
        case .browse: showBrowser()
        case .reader:
            if isPlaying {
                showNowPlaying()
            } else if let resume {
                resume()
            } else {
                showToast(ShellToast(message: String(localized: "Nothing to listen to yet. Play a page, then tap Listen."),
                                     systemImage: Icons.listen))
            }
        }
    }

    // MARK: - The Reader

    /// The Reader on `article`, over the surface on screen. The page you hear opens as Now
    /// Playing instead: the Reader never shows what is playing.
    func openReader(_ article: ReaderArticle) {
        if isHearingArticle(of: article) {
            showNowPlaying()
            return
        }
        reader = ReaderSheetState(article: article, origin: isInLibrary ? .library : .browser)
    }

    /// The Browser's page in place (`pageReader`); nothing if the user left the Browser (or ended the
    /// reader) since `epoch`. Never switches destination, even for the page you hear. Opens with the
    /// chrome expanded: it has no scroll to bring row 2 back.
    func openPageReader(_ article: ReaderArticle, requestedAt epoch: Int) {
        guard epoch == pageReaderEpoch, isBrowsing, reader == nil, !isNowPlayingPresented else { return }
        pageReader = article
        chromeScroll.expand()
    }

    /// A Library page's text in place of the Library (`libraryReader`), with the chrome expanded.
    func openLibraryReader(_ article: ReaderArticle) {
        guard isInLibrary, reader == nil, !isNowPlayingPresented else { return }
        endLibrarySearch()
        libraryReader = article
        chromeScroll.expand()
    }

    /// The Library again, where it was.
    func closeLibraryReader() {
        libraryReader = nil
    }

    /// The page itself again.
    func closePageReader() {
        pageReader = nil
        readerAppearanceOpen = false
        pageReaderEpoch += 1
    }

    // MARK: - ‹ › through reader mode

    /// The page whose in-place reader view ‹ left: › to it shows the reader view again, as it was
    /// when you went back. (The reader view isn't a history entry of its own: the web view's history
    /// holds the pages, so the shell remembers the one page.)
    private(set) var readerLeftByBack: URL?
    /// › was pressed toward `readerLeftByBack`: its reader view opens once that page has loaded.
    private(set) var readerToReenter: URL?

    /// ‹ in the Browser (the button or the reader view's edge swipe).
    func browserWillGoBack() {
        readerLeftByBack = pageReader != nil ? web.currentURL : nil
        readerToReenter = nil
    }

    /// › in the Browser.
    func browserWillGoForward() {
        readerToReenter = readerLeftByBack
        readerLeftByBack = nil
    }

    /// The page `readerToReenter` names has loaded and is readable: true once, then it is spent.
    /// Any other page drops the request.
    func takeReaderToReenter() -> Bool {
        guard let url = readerToReenter, !web.isLoading, web.isReaderable, web.currentURL == url, pageReader == nil else { return false }
        readerToReenter = nil
        return true
    }

    /// Whether `article`'s page is what you hear: by key, or a web page by its address.
    func isHearingArticle(of article: ReaderArticle) -> Bool {
        isHearing(.article(article.id)) || article.origin.canonicalURL.map { isHearing(.webPage(canonicalURL: $0)) } == true
    }

    /// Updates the Reader's article in place (favicon arrived, listen blocks built, Save
    /// rekeyed it), if that article is still the one shown.
    func updateReader(id: UUID, _ change: (inout ReaderArticle) -> Void) {
        if pageReader?.id == id { change(&pageReader!) }
        if libraryReader?.id == id { change(&libraryReader!) }
        guard var state = reader, state.article.id == id else { return }
        change(&state.article)
        reader = state
    }

    /// The Reader sheet shown as `presentation` has gone (regular width: its back pill, the grabber's
    /// pull down, after its own close animation). A Reader opened since stays.
    func readerDidClose(_ presentation: UUID) {
        guard reader?.presentation == presentation else { return }
        reader = nil
    }

    // MARK: - Now Playing

    /// The chrome's Reader segment, the bar's tap and swipe up, crash resume. Over everything; the
    /// surface and its state (the page, the Library) stay as they are underneath. A Reader of the page you hear closes,
    /// so the two never show the same page.
    func showNowPlaying() {
        presentNowPlayingOnTop()
    }

    /// Crash resume: Listen straight at launch, with nowhere to go back to (no ‹).
    func resumeNowPlayingAtLaunch() {
        listenLaunch = nil
        presentNowPlayingOnTop()
    }

    private func presentNowPlayingOnTop() {
        endAddressSearch()
        if let article = reader?.article, isHearingArticle(of: article) {
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

    /// Regular width: ⌄ or the pull down, after the close animation of the showing `presentation`. A Now Playing
    /// shown since stays.
    func nowPlayingDidClose(_ presentation: UUID) {
        guard nowPlayingPresentation == presentation else { return }
        hideNowPlaying()
    }

    /// How the Reader or Now Playing shows: a sheet on regular width, else in place under the chrome.
    /// What a reading page shown in place needs from the compact chrome: its scroll feeds the one
    /// scroll controller (the same rule as the Library's and the Browser's), its full screen removes
    /// the chrome, and the text keeps the card's room whether the chrome is expanded or folded.
    func readingShowing(regular: Bool, close: SheetClosePill.Kind, onClose: @escaping () -> Void) -> ReadingShowing {
        regular ? .sheet(close: close, onClose: onClose) : .inPlace(readingInPlace)
    }

    private var readingInPlace: ReadingInPlace {
        readingInPlace(bottomClearance: ChromeMetrics.readerFootprint,
                       overTextClearance: chromeScroll.isCollapsed ? ChromeMetrics.collapsedFootprint : ChromeMetrics.readerFootprint)
    }

    /// The Library's Read and the Browser's reader mode in place: the chrome there never folds and has
    /// no card, so the text keeps clear of its two rows and what floats over it sits above them.
    var pageReadingInPlace: ReadingInPlace {
        readingInPlace(bottomClearance: ChromeMetrics.footprint, overTextClearance: ChromeMetrics.footprint)
    }

    private func readingInPlace(bottomClearance: CGFloat, overTextClearance: CGFloat) -> ReadingInPlace {
        ReadingInPlace(
            bottomClearance: bottomClearance,
            overTextClearance: overTextClearance,
            scrolled: { [chromeScroll] in chromeScroll.scrolled(to: $0) },
            anchored: { [chromeScroll] in chromeScroll.anchor(at: $0) },
            fullScreen: Binding(get: { [chromeScroll] in chromeScroll.fullScreen }, set: { [chromeScroll] in chromeScroll.setFullScreen($0) }))
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
        if let wanted = readerToReenter, web.currentURL != wanted { readerToReenter = nil }
        closePageReader()
        chromeScroll.expand()
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
        closePageReader()
        reader = nil
        hideNowPlaying()
        surface = .library
    }

    /// Back to the browser as it was: the page (or start page) under the library is untouched. A
    /// Reader opened from the library goes with it.
    func leaveLibrary() {
        guard isInLibrary else { return }
        endLibrarySearch()
        libraryReader = nil
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
        closePageReader()
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
        librarySearchFolder = nil
    }

    /// The Library's field tapped: a search of the screen on top, the home's tab or a folder,
    /// which it keeps until it ends.
    func beginLibrarySearch() {
        if case .folder(let id) = libraryPath.last { librarySearchFolder = id } else { librarySearchFolder = nil }
        librarySearch.begin()
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

    /// A library page in the Reader (a row, a favorite): shown as soon as
    /// the page is read; older pages build their listen blocks afterwards.
    func openSaved(_ id: UUID, in library: LibraryStore, inPlace: Bool = false) {
        Task {
            var shown = false
            await ReaderArticle.loadSaved(id: id, in: library) { article in
                if shown {
                    updateReader(id: article.id) { $0 = article }
                } else {
                    shown = true
                    if inPlace { openLibraryReader(article) } else { openReader(article) }
                }
            }
        }
    }
}
