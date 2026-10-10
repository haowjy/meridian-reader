#if DEBUG
import Foundation

/// Launch arguments, parsed once (Debug builds only). UI tests and diagnostics drive the app
/// through these; a normal launch has none of them.
struct LaunchOptions: Equatable {
    /// `-seedDemoArticle`: the library is replaced by one deterministic demo article.
    struct DemoArticle: Equatable {
        /// `-seedDemoTitle "<title>"` (long-title layout checks).
        var title: String?
        /// `-seedDemoParagraphs N`: a longer article (background-listening probe). At least 3.
        var paragraphs = 3
        /// `-seedDemoProgress N`: saved playhead paragraph (resume checks).
        var progress = 0
        /// `-seedDemoPlainText`: the article has no HTML, only its plain text.
        var plainTextOnly = false
        /// `-seedPlayedPages N`: also N pages played without saving, part-way ("Played Page 1"
        /// played most recently): the "Not saved" rows at the top of the Library's *Pages*.
        var playedPages = 0
    }

    enum BookmarkSetup: Equatable {
        /// `-resetBookmarks`: start with none.
        case reset
        /// `-seedBookmarks`: start with a fixed few.
        case seed
    }

    /// `-uiTesting`: expose test-only accessibility markers and skip network-dependent features
    /// (live Google suggestions), so results don't depend on the network.
    var uiTesting = false
    var demoArticle: DemoArticle?
    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): start in the reader overlay on it.
    var opensDemoInReader = false
    /// `-openLibrary`: start in the library.
    var opensLibrary = false
    /// `-browseTestPages`: serve and open the offline `reader-test://` pages.
    var servesTestPages = false
    var bookmarks: BookmarkSetup?
    /// `-bakeArticle <id prefix>`: render that saved article's audio top-down without playing.
    var bakeArticlePrefix: String?
    /// `-scrubBubbleDemo` (with `-uiTesting`): freeze a mid-drag scrubber frame for a screenshot.
    var scrubBubbleDemo = false
    /// `-slowMenuAnimation`: slow the ⋯ morph so a mid-animation frame can be captured.
    var slowMenuAnimation = false
    /// `-rerunLibraryMigration`: delete every folder, page and migration receipt, then copy the
    /// saved articles and bookmarks again.
    var rerunsLibraryMigration = false
    /// `-seedDemoBook`: add the demo book and its page in no folder (`DemoBook`), replacing the
    /// ones an earlier launch added. The rest of the library is left alone.
    var seedsDemoBook = false
    /// `-seedDemoBookPlace N` (with `-seedDemoBook`): the book's place is chapter N (its index in
    /// `DemoBook.chapters`; 0 is the title page), at its third paragraph, the chapters before it
    /// finished: a book part-way, for its row's place and ▶.
    var demoBookPlace: Int?
    /// `-chainDemoChapters`: once launched, play the demo book from its place (chapter 1 the first
    /// time) and let it carry on (the locked-screen device check).
    var chainsDemoChapters = false
    /// `-seedDemoFolders`: add a "Demo Finance" folder with two subfolders and saved pages (one in a
    /// subfolder), replacing the one an earlier launch added.
    var seedsDemoFolders = false
    /// `-restoreSurface` (with `-uiTesting`): reopen on the remembered surface, as a normal launch
    /// does (decision D10). Without it a UI-test launch starts on the browser, whatever an earlier
    /// test left, and `-browseTestPages` loads page one.
    var restoresSurfaceInUITests = false
    /// `-resetSurface`: forget the remembered surface first, as on a fresh install.
    var resetsSurface = false
    /// `-importTestEPUB`: *Import Book…* imports the synthetic EPUB (`TestEPUB`) instead of
    /// opening the Files picker, which a UI test can't drive. At launch an earlier import of it is
    /// deleted, with its audio, so it imports fresh.
    var importsTestEPUB = false
    /// `-playTestEPUB`: at launch, import the synthetic EPUB into the Library's top level (no
    /// sheet), then play it from its place, as a book's Play does.
    var playsTestEPUB = false
    /// `-failLibrarySaves`: once the launch work is done (seeds, maintenance, bookmarks), every
    /// library save fails, so UI tests see the edits that can't be saved.
    var failsLibrarySaves = false
    /// `-probeLockedFetch`: once launched, the locked-phone device check of a hidden fetch and a
    /// silent wait between chapters (`LockedFetchProbe`). It runs only in the probe's own install.
    var probesLockedFetch = false

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        let flags = Set(arguments)
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        uiTesting = flags.contains("-uiTesting")
        if flags.contains("-seedDemoArticle") {
            demoArticle = DemoArticle(
                title: value(after: "-seedDemoTitle"),
                paragraphs: max(3, value(after: "-seedDemoParagraphs").flatMap(Int.init) ?? 3),
                progress: value(after: "-seedDemoProgress").flatMap(Int.init) ?? 0,
                plainTextOnly: flags.contains("-seedDemoPlainText"),
                playedPages: value(after: "-seedPlayedPages").flatMap(Int.init) ?? 0
            )
        }
        opensDemoInReader = flags.contains("-openDemoInBrowseReader")
        opensLibrary = flags.contains("-openLibrary")
        servesTestPages = flags.contains("-browseTestPages")
        if flags.contains("-seedBookmarks") {
            bookmarks = .seed
        } else if flags.contains("-resetBookmarks") {
            bookmarks = .reset
        }
        bakeArticlePrefix = value(after: "-bakeArticle")?.uppercased()
        scrubBubbleDemo = uiTesting && flags.contains("-scrubBubbleDemo")
        slowMenuAnimation = flags.contains("-slowMenuAnimation")
        rerunsLibraryMigration = flags.contains("-rerunLibraryMigration")
        seedsDemoBook = flags.contains("-seedDemoBook")
        demoBookPlace = value(after: "-seedDemoBookPlace").flatMap(Int.init)
        chainsDemoChapters = flags.contains("-chainDemoChapters")
        seedsDemoFolders = flags.contains("-seedDemoFolders")
        restoresSurfaceInUITests = flags.contains("-restoreSurface")
        resetsSurface = flags.contains("-resetSurface")
        importsTestEPUB = flags.contains("-importTestEPUB")
        playsTestEPUB = flags.contains("-playTestEPUB")
        failsLibrarySaves = flags.contains("-failLibrarySaves")
        probesLockedFetch = flags.contains("-probeLockedFetch")
    }

    /// Whether the app reopens on the surface it was left on.
    var restoresSurface: Bool { !uiTesting || restoresSurfaceInUITests }

    /// Live Google suggestions in the address field.
    var fetchesSuggestions: Bool { !uiTesting }
}
#endif
