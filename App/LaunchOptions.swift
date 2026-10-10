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
        /// `-seedDemoProgress N`: saved playhead paragraph ("Continue listening" checks).
        var progress = 0
        /// `-seedDemoPlainText`: the article has no HTML, only its plain text.
        var plainTextOnly = false
        /// `-seedPlayedPages N`: also N pages played without saving, part-way ("Played Page 1"
        /// played most recently), so Continue has more rows than it shows folded.
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
    }

    /// Live Google suggestions in the address field.
    var fetchesSuggestions: Bool { !uiTesting }
}
#endif
