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

/// A page pushed in Settings (Settings › Voice).
enum SettingsRoute: String, Hashable {
    case voice, speed, appearance, reading, preparedAudio, acknowledgements
}

/// The Reader sheet: a page shown for reading over the surface that opened it, on regular width.
/// Compact width reads in place instead (`ShellState.libraryReader`, `pageReader`).
struct ReaderSheetState: Equatable {
    var article: ReaderArticle
    var origin: ReaderOrigin
    /// This showing of the Reader. A sheet's close reports it (`readerDidClose`), so a close that
    /// lands late can't remove a Reader opened since.
    let presentation = UUID()
}

/// The shell’s sheets, shown one at a time by its `.sheet(item:)`.
enum ShellSheet: Identifiable, Equatable {
    case pasteText(UUID?)
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
        case .pasteText(let id): "pasteText-\(id?.uuidString ?? "root")"
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

/// A short message over the bottom chrome ("Nothing to listen to on this page"), with an optional action button.
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
        /// Settings in place, compact width only (regular width shows it as a sheet, `showSettings`).
        case settings
    }

    /// The compact bottom chrome's presence (collapsed to one row, an in-place reader's full screen) and
    /// the one scroll controller the Library, the Browser and the in-place readers feed.
    let chromeScroll = ChromeScroll()

    private(set) var surface: Surface = .browse {
        didSet {
            remember()
            syncChromeOwner()
        }
    }
    /// The Library's pushed screens, nearest the home first (`[.folder(Fiction), .folder(Short
    /// stories)]`). Kept while the browser is up, so 🌐 and back return to the same folder.
    var libraryPath: [LibraryRoute] = [] {
        didSet {
            remember()
            syncChromeOwner()
            if let folder = librarySearchFolder, !libraryPath.contains(.folder(folder)) { endLibrarySearch() }
        }
    }
    /// The folder the Library's search searches: the folder screen on top when it began (nil:
    /// the home, which searches its tab). It ends once that folder leaves the path.
    private(set) var librarySearchFolder: UUID?
    /// The Library home's tab (`LibraryHomeTab`). Its picker sets it; going to a place in the
    /// Library shows Everything (`showLibrary(at:)`), and 📚 keeps it. Remembered with the surface.
    var homeTab = LibraryHomeTab.everything {
        didSet { memory?.saveHomeTab(homeTab) }
    }
    /// The Reader sheet (nil = closed; regular width only). Its close ends it through `readerDidClose`
    /// once it has gone.
    private(set) var reader: ReaderSheetState? {
        didSet { syncChromeOwner() }
    }
    /// The Browser's page as the Reader draws it, in place of the page (nil = the page itself).
    /// The address pill's reader icon toggles it; it is the page's own, so it ends when the page changes.
    /// It stays while another destination shows, so the Browser comes back as it was left.
    private(set) var pageReader: ReaderArticle? {
        didSet { syncChromeOwner() }
    }
    /// The Browser's page (`browserPageChanged`), the browser's screen as the chrome knows it: a new page
    /// is a new screen, handed over like any other, so a page that changes under another destination or
    /// a cover leaves that screen's chrome alone and starts expanded when the Browser shows again.
    private(set) var browserPage: URL? {
        didSet { syncChromeOwner() }
    }
    /// A Library page read in place (Library *Read*): its text replaces the Library's content, like the
    /// Browser's reader mode, under the same chrome with the Library segment lit. Nothing plays until
    /// the top group's ▶ Listen (which raises Now Playing over it); ‹ (or the edge swipe) puts the
    /// Library back as it was.
    private(set) var libraryReader: ReaderArticle? {
        didSet { syncChromeOwner() }
    }
    /// Compact width reads in place (`libraryReader`, `pageReader`) and has Settings as a destination;
    /// regular width keeps the Reader sheet and the Settings sheet, so a Settings surface (restored, or
    /// the window widened) becomes the browser with the Settings sheet over it.
    var isCompact = false {
        didSet {
            guard !isCompact, isInSettings else { return }
            showBrowser()
            present(.settings)
        }
    }
    /// Counts the endings of an in-place reader (`closePageReader`): an extraction that began
    /// under an earlier count opens nothing (the user left, or the page moved on, meanwhile).
    private(set) var pageReaderEpoch = 0
    /// This showing of Now Playing (nil = down), Listen: over everything, the compact chrome
    /// included. It shows what you hear, so it holds no article of its own. Its close reports the
    /// showing it closed (`nowPlayingDidClose`), so a close that lands late can't take down a newer one.
    private(set) var nowPlayingPresentation: UUID? {
        didSet { syncChromeOwner() }
    }
    var isNowPlayingPresented: Bool { nowPlayingPresentation != nil }
    /// Where Now Playing's text opens: the Reader's scroll position (its reading page's
    /// `handOver`) when its Listen turned it into Now Playing (it appears in place, without
    /// rising). nil = it rises and finds the audio.
    private(set) var nowPlayingOpensAt: ReadingHandOver?
    var sheet: ShellSheet? {
        didSet {
            if sheet == nil { overSheet = nil }
            syncChromeOwner()
        }
    }
    /// A sheet over `sheet` (`ShellSheet.showsOverASheet`); it goes with it.
    var overSheet: ShellSheet?
    /// *Import Book…*'s Files picker is up (`pickBook(into:)`).
    var isPickingBook = false {
        didSet { syncChromeOwner() }
    }
    /// Where the picked book goes (nil: the Library's top level).
    private(set) var bookPickDestination: UUID?
    /// A short message over the bottom chrome of the surface on screen.
    private(set) var toast: ShellToast?
    var busy: BusyAction?
    let web = WebViewStore()
    /// The browser's address field. Idle, its text is the page's address.
    let addressSearch = SearchSession()
    /// The Library's search field, in the band (decision D22): its text filters the Library home.
    let librarySearch = SearchSession()
    /// Search Settings, the Settings destination's field: its text filters the settings list.
    let settingsSearch = SearchSession()
    /// The Settings destination's pushed pages, kept while another destination shows.
    var settingsPath: [SettingsRoute] = [] {
        didSet { syncChromeOwner() }
    }
    /// Regular-width sidebar collapsed for focus reading / full-bleed Browse (iPad). Compact ignores it.
    var sidebarCollapsed = false
    /// Whether a target is what you hear (the playback session answers).
    private let isHearing: (ListenTarget) -> Bool

    /// ⋯ › Help and Settings › About: opens the welcome article (`WelcomeArticle.open`), wired
    /// where the library exists (`ReaderApp`).
    var openWelcome: () -> Void = {}

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
        // Observers don't run in an initializer: the restored surface is handed over on the way out.
        defer { syncChromeOwner() }
        guard restores, let memory else { return }
        homeTab = memory.loadHomeTab()
        if let last = memory.load() {
            surface = switch last.base {
            case .library: .library
            case .browse: .browse
            case .settings: .settings
            }
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

    /// The screen whose scrolling moves the compact chrome: the one showing (a pushed page, the
    /// Browser's page and a page read in place are screens of their own), and nothing while Listen, the Reader or any sheet (the
    /// Files picker included) covers it. Every property it reads calls `syncChromeOwner` when it
    /// changes, so the controller's owner is never out of step.
    var chromeOwner: ChromeOwner? {
        if isNowPlayingPresented || reader != nil || sheet != nil || isPickingBook { return nil }
        return switch surface {
        case .browse: pageReader.map { ChromeOwner(source: .browserReader, screen: $0.id) }
            ?? ChromeOwner(source: .browser, screen: browserPage)
        case .library: libraryReader.map { ChromeOwner(source: .libraryReader, screen: $0.id) }
            ?? ChromeOwner(source: .library, screen: libraryPath)
        case .settings: ChromeOwner(source: .settings, screen: settingsPath)
        }
    }

    var isInSettings: Bool {
        if case .settings = surface { true } else { false }
    }

    /// Hands `chromeOwner` to the controller, synchronously with the change that moved it.
    private func syncChromeOwner() {
        chromeScroll.hand(to: chromeOwner)
    }

    /// `path` up to its first folder that no longer exists: a deleted folder falls back to its
    /// nearest surviving parent, at worst the Library's home.
    static func surviving(_ path: [LibraryRoute], exists: (UUID) -> Bool) -> [LibraryRoute] {
        Array(path.prefix { route in
            switch route { case .folder(let id): exists(id) }
        })
    }

    // MARK: - The chrome's destination

    /// The pill's lit segment: the surface on screen. Listen covers it without changing it.
    var chromeDestination: ChromeDestination {
        switch surface {
        case .browse: .browse
        case .library: .library
        case .settings: .settings
        }
    }

    /// A tap on a segment of the chrome's pill. The lit segment is where you already are.
    func select(_ target: ChromeDestination) {
        guard target != chromeDestination else { return }
        switch target {
        case .library: openLibrary()
        case .browse: showBrowser()
        case .settings: showSettings()
        }
    }

    // MARK: - The Reader

    /// `article` for reading. The page you hear opens as Now Playing instead: no reader shows what is
    /// playing. Regular width: the Reader sheet over the surface on screen. Compact width: the
    /// Library's Read, in place (from the browser too: a saved page is the Library's, not the page's).
    func openReader(_ article: ReaderArticle) {
        if isHearingArticle(of: article) {
            showNowPlaying()
            return
        }
        guard isCompact else {
            reader = ReaderSheetState(article: article, origin: isInLibrary ? .library : .browser)
            return
        }
        openLibrary()
        openLibraryReader(article)
    }

    /// The Browser's page in place (`pageReader`); nothing if the user left the Browser (or ended the
    /// reader) since `epoch`. Never switches destination, even for the page you hear. A new screen for
    /// the chrome, so it opens expanded: it has no scroll to bring row 2 back.
    func openPageReader(_ article: ReaderArticle, requestedAt epoch: Int) {
        guard epoch == pageReaderEpoch, isBrowsing, reader == nil, !isNowPlayingPresented else { return }
        pageReader = article
    }

    /// A Library page's text in place of the Library (`libraryReader`), a new screen for the chrome.
    func openLibraryReader(_ article: ReaderArticle) {
        guard isInLibrary, reader == nil, !isNowPlayingPresented else { return }
        endLibrarySearch()
        libraryReader = article
    }

    /// The Library again, where it was.
    func closeLibraryReader() {
        libraryReader = nil
    }

    /// The page itself again.
    func closePageReader() {
        pageReader = nil
        pageReaderEpoch += 1
    }

    // MARK: - Pages that open in reader view

    /// The page whose in-place reader view ‹ left: › to it shows the reader view again, as it was
    /// when you went back. (The reader view isn't a history entry of its own: the web view's history
    /// holds the pages, so the shell remembers the one page.)
    private(set) var readerLeftByBack: URL?
    /// The page whose reader view opens once it has loaded: `readerLeftByBack` after ›, or a page
    /// shared from another app (`navigate(to:inReader:)`). A redirect while it loads carries it to
    /// where the load lands.
    private(set) var readerOnLoad: URL?

    /// ‹ in the Browser (the button or the reader view's edge swipe).
    func browserWillGoBack() {
        readerLeftByBack = pageReader != nil ? web.currentURL : nil
        readerOnLoad = nil
    }

    /// › in the Browser.
    func browserWillGoForward() {
        readerOnLoad = readerLeftByBack
        readerLeftByBack = nil
    }

    /// The page `readerOnLoad` names has loaded and is readable: true once, then it is spent.
    /// Any other page drops the request.
    func takeReaderOnLoad() -> Bool {
        guard let url = readerOnLoad, !web.isLoading, web.isReaderable, web.currentURL == url, pageReader == nil else { return false }
        readerOnLoad = nil
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

    /// Listen: the chrome's Listen button, a reader's ▶ Listen, the bar's tap and swipe up, crash
    /// resume. Over everything; the surface and its state (the page, the Library, a search, a reader
    /// and its scroll) stay as they are underneath, so closing it is back where you were. A Reader
    /// sheet of the page you hear closes, so the two never show the same page.
    func showNowPlaying() {
        // A search stays open under Listen, its keyboard lowered.
        addressSearch.lowerKeyboard()
        librarySearch.lowerKeyboard()
        settingsSearch.lowerKeyboard()
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

    /// ⌄ or the pull down, after the close animation of the showing `presentation`. A Now Playing
    /// shown since stays.
    func nowPlayingDidClose(_ presentation: UUID) {
        guard nowPlayingPresentation == presentation else { return }
        hideNowPlaying()
    }

    /// The Library's Read and the Browser's reader mode in place: the end of the text scrolls to just
    /// above the chrome's two rows (a reader's chrome never folds), and its scroll and full screen are
    /// the chrome's, reported as `source` (`.browserReader`, `.libraryReader`).
    func pageReadingInPlace(_ source: ChromeSource) -> ReadingInPlace {
        ReadingInPlace(
            bottomClearance: ChromeHome.clearance(step: 0),
            homeIndicator: ChromeHome.inset,
            scrolled: { [chromeScroll] in chromeScroll.scrolled(to: $0, from: source) },
            anchored: { [chromeScroll] in chromeScroll.anchor(at: $0, from: source) },
            fullScreen: Binding(get: { [chromeScroll] in chromeScroll.fullScreen }, set: { [chromeScroll] in chromeScroll.setFullScreen($0, from: source) }))
    }

    // MARK: - Remembering the surface

    /// At launch, once the library is open: the path keeps the folders that still exist (up to the
    /// first that doesn't), and the browser reloads its last page: now when it is showing, or the
    /// first time you go there from another surface (`showBrowser`).
    func restoreAtLaunch(folderExists: (UUID) -> Bool) {
        pruneLibraryPath(keeping: folderExists)
        if isBrowsing, let url = pendingBrowserURL {
            pendingBrowserURL = nil
            navigate(to: url)
        }
    }

    /// The browser's page changed: the chrome's screen (`browserPage`), its address field, and the page
    /// to reopen on.
    func browserPageChanged() {
        if let wanted = readerOnLoad, web.currentURL != wanted { readerOnLoad = web.isLoading ? web.currentURL : nil }
        browserPage = web.currentURL
        closePageReader()
        syncAddressField()
        remember()
    }

    private func remember() {
        guard let memory else { return }
        let base: SurfaceMemory.Base = switch surface {
        case .browse: .browse
        case .library: .library
        case .settings: .settings
        }
        memory.save(SurfaceMemory(base: base, libraryPath: libraryPath,
                                  browserURL: (web.currentURL ?? pendingBrowserURL)?.absoluteString))
    }

    // MARK: - Library navigation

    /// The Library's path up to the first folder that no longer exists (it was deleted).
    func pruneLibraryPath(keeping folderExists: (UUID) -> Bool) {
        let kept = Self.surviving(libraryPath, exists: folderExists)
        if kept != libraryPath { libraryPath = kept }
    }

    /// A place in the Library (*Go to* a folder or the Library, an imported book): the Library at
    /// `path` (a folder pushed under the folders above it, or `[]` for the home), on Everything,
    /// where every place shows.
    func showLibrary(at path: [LibraryRoute]) {
        openLibrary()
        // A place in the Library asked for by name: a page read in place would cover it.
        closeLibraryReader()
        libraryPath = path
        homeTab = .everything
    }

    // MARK: - Surfaces

    /// 📚: the Library as it was left, its place and its tab.
    func openLibrary() {
        reader = nil
        hideNowPlaying()
        show(.library)
    }

    /// The browser as it was, with nothing over it (the Reader, Now Playing): the page (or start page)
    /// under the other surfaces is untouched.
    func showBrowser() {
        reader = nil
        hideNowPlaying()
        guard !isBrowsing else { return }
        show(.browse)
        // Reopened elsewhere: the browser's last page loads the first time you go there.
        if let url = pendingBrowserURL, web.currentURL == nil {
            pendingBrowserURL = nil
            navigate(to: url)
        }
    }

    /// Settings: on compact width the Settings destination, in place under the chrome (a sheet that
    /// asked for it closes); on regular width the Settings sheet.
    func showSettings() {
        guard isCompact else {
            present(.settings)
            return
        }
        sheet = nil
        hideNowPlaying()
        show(.settings)
    }

    /// `new` on screen: what belonged only to the surface it replaces goes (its search, a Library page
    /// read in place, a Reader opened from the Library). What it shows stays for the next visit, the
    /// Browser's reader mode included.
    private func show(_ new: Surface) {
        guard surface != new else { return }
        switch surface {
        case .browse:
            endAddressSearch()
        case .library:
            endLibrarySearch()
            libraryReader = nil
            if reader?.origin == .library { reader = nil }
        case .settings:
            endSettingsSearch()
        }
        surface = new
    }

    // MARK: - Pages

    /// Shows `url` in the browser: ends the address search, leaves the reader or library, loads.
    /// Every way of going to a page (submitted address, bookmark, history, Website, Share) ends
    /// here. `inReader` (Share): its reader view opens once it has loaded, if it is readable.
    func navigate(to url: URL, inReader: Bool = false) {
        // A page asked for (a share at a cold start too) replaces the remembered one.
        pendingBrowserURL = nil
        readerOnLoad = inReader ? url : nil
        closePageReader()
        addressSearch.end(showing: Self.addressText(for: url))
        showBrowser()
        web.load(url)
    }

    /// The article's own page: revealed as it is when it's the page already loaded (no reload,
    /// scroll kept), else loaded. Audio keeps playing. Either way it is the web page: a reader view
    /// kept from an earlier visit to the Browser closes.
    func openWebsite(_ url: URL) {
        if let current = web.currentURL, current.isSamePage(as: url) {
            closePageReader()
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

    /// Search Settings' field tapped: the search shows its results on the list, so a pushed page goes.
    func beginSettingsSearch() {
        settingsPath = []
        settingsSearch.begin()
    }

    /// Search Settings' ✕ (or leaving Settings): ends its search and clears the filter.
    func endSettingsSearch() {
        settingsSearch.end(showing: "")
    }

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

    /// A library page in the Reader (a row): shown as soon as
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
