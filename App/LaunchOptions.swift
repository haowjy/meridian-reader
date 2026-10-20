#if DEBUG
import Foundation

/// Launch arguments, parsed once (Debug builds only). Probes of the running app, the UI tests
/// and diagnostics drive the app through these; a normal launch has none of them.
struct LaunchOptions: Equatable {
    /// `-seedDemoArticle`: one deterministic demo article.
    struct DemoArticle: Equatable {
        /// `-seedDemoPlainText`: the article has no HTML, only its plain text.
        var plainTextOnly = false
        /// `-seedPlayedPages N`: also N pages played without saving, part-way ("Played Page 1"
        /// played most recently): the Library's Recent tab.
        var playedArticles = 0
    }

    /// `-uiTesting`: expose test-only accessibility markers and skip network-dependent features
    /// (live Google suggestions), so results don't depend on the network.
    var uiTesting = false
    /// `-resetLibrary`: start as a fresh install does. Before anything reads them, the stored
    /// settings go (every owner's `storedKeys`: the engine, the voices and each voice library's own
    /// settings, language and speed, both appearances, the remembered surface and the Library's tab
    /// and sort, Recent Searches, Block Ads, developer options and Listen Debug) with the download list (`LaunchHooks.resetStoredSettings`). Before the seeds, the
    /// library's every page (link pages too) and folder go, with their audio, and the browsing
    /// history (`LaunchHooks.resetLibrary`). The seeds then add to an empty library. Every UI
    /// test launches with it.
    var resetsLibrary = false
    var demoArticle: DemoArticle?
    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): start in the reader overlay on it.
    var opensDemoInReader = false
    /// `-openLibrary`: start in the library.
    var opensLibrary = false
    /// `-browseTestPages`: serve and open the offline `reader-test://` pages.
    var servesTestPages = false
    /// `-testStoryChapters N`: the offline story's table of contents (`reader-test://story/toc`)
    /// lists N chapters (8 without it), so a check finds new ones on a later launch.
    var testStoryChapters = 8
    /// `-testStoryThrottles`: the offline story's chapter 6 doesn't load the first time it is
    /// asked for in a launch (a site not answering), for Follow's back-off.
    var testStoryThrottles = false
    /// `-seedBookmarks`: a few starred `example.com` links whose icons stay letter tiles (no
    /// fetch).
    var seedsBookmarks = false
    /// `-seedHistory`: a few visited `example.com` pages in the browser's History (one untitled).
    var seedsHistory = false
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
    /// ones an earlier launch added (it also runs on a phone, without `-resetLibrary`). The rest
    /// of the library is left alone.
    var seedsDemoBook = false
    /// `-seedDemoBookPlace N` (with `-seedDemoBook`): the book's place is chapter N (its index in
    /// `DemoBook.chapters`; 0 is the title page), at its third paragraph, the chapters before it
    /// finished: a book part-way, for its row's place and ▶.
    var demoBookPlace: Int?
    /// `-chainDemoChapters`: once launched, play the demo book from its place (chapter 1 the first
    /// time) and let it carry on (the locked-screen device check).
    var chainsDemoChapters = false
    /// `-seedDemoFolders`: add a "Demo Finance" folder with two subfolders and saved pages (one in a
    /// subfolder).
    var seedsDemoFolders = false
    /// `-seedBigFolder N`: add "Big Folder" with N saved pages (the menu and row timing probe, C98).
    var bigFolderArticles = 0
    /// `-restoreSurface` (with `-uiTesting`): reopen on the remembered surface, as a normal launch
    /// does (decision D10). Without it a UI-test launch starts on the browser, whatever an earlier
    /// test left, and `-browseTestPages` loads page one.
    var restoresSurfaceInUITests = false
    /// `-importTestEPUB`: *Import Book…* imports the synthetic EPUB (`TestEPUB`) instead of
    /// opening the Files picker, which a UI test can't drive.
    var importsTestEPUB = false
    /// `-playTestEPUB`: at launch, import the synthetic EPUB into the Library's top level (no
    /// sheet), then play it from its place, as a book's Play does.
    var playsTestEPUB = false
    /// `-failLibrarySaves`: once the launch work is done (seeds, maintenance, bookmarks), every
    /// library save fails, so UI tests see the edits that can't be saved.
    var failsLibrarySaves = false
    /// `-testVoice`: register an offline on-device test voice (`TestVoiceProvider`, "Test Voice"
    /// with voices One and Two); `-selectEngine test.voice` picks it. Downloads render with it.
    var usesTestVoice = false
    /// `-selectEngine <engine id>` (`local.kokoro`, `apple`, `test.voice`): the engine to load at
    /// launch, persisted as the selection.
    var selectsEngine: SpeechEngineID?
    /// `-kokoroUnits <label>`: compute units of Kokoro's Core ML route (`KokoroHost.unitsLabel`).
    var kokoroUnits: String?
    /// `-engineProbe [-probeOnly Kokoro,…] [-probeStress [-probeStressN n]]`: time every on-device
    /// engine once launched (`EngineLatencyProbe`).
    var engineProbe: EngineLatencyProbe.Request?
    /// `-KokoroStress coreml|onnx [-KokoroStressCalls n] [-KokoroStressFresh]`: the Kokoro crash
    /// and speed run (`KokoroStressRun`).
    var kokoroStress: KokoroStressRun.Request?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        let flags = Set(arguments)
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        uiTesting = flags.contains("-uiTesting")
        resetsLibrary = flags.contains("-resetLibrary")
        if flags.contains("-seedDemoArticle") {
            demoArticle = DemoArticle(plainTextOnly: flags.contains("-seedDemoPlainText"),
                                      playedArticles: value(after: "-seedPlayedPages").flatMap(Int.init) ?? 0)
        }
        opensDemoInReader = flags.contains("-openDemoInBrowseReader")
        opensLibrary = flags.contains("-openLibrary")
        servesTestPages = flags.contains("-browseTestPages")
        testStoryChapters = value(after: "-testStoryChapters").flatMap(Int.init) ?? testStoryChapters
        testStoryThrottles = flags.contains("-testStoryThrottles")
        seedsBookmarks = flags.contains("-seedBookmarks")
        seedsHistory = flags.contains("-seedHistory")
        bakeArticlePrefix = value(after: "-bakeArticle")?.uppercased()
        scrubBubbleDemo = uiTesting && flags.contains("-scrubBubbleDemo")
        slowMenuAnimation = flags.contains("-slowMenuAnimation")
        rerunsLibraryMigration = flags.contains("-rerunLibraryMigration")
        seedsDemoBook = flags.contains("-seedDemoBook")
        demoBookPlace = value(after: "-seedDemoBookPlace").flatMap(Int.init)
        chainsDemoChapters = flags.contains("-chainDemoChapters")
        seedsDemoFolders = flags.contains("-seedDemoFolders")
        bigFolderArticles = value(after: "-seedBigFolder").flatMap(Int.init) ?? 0
        restoresSurfaceInUITests = flags.contains("-restoreSurface")
        importsTestEPUB = flags.contains("-importTestEPUB")
        playsTestEPUB = flags.contains("-playTestEPUB")
        failsLibrarySaves = flags.contains("-failLibrarySaves")
        usesTestVoice = flags.contains("-testVoice")
        selectsEngine = value(after: "-selectEngine").map(SpeechEngineID.init(rawValue:))
        kokoroUnits = value(after: "-kokoroUnits")
        if flags.contains("-engineProbe") {
            engineProbe = EngineLatencyProbe.Request(
                engines: value(after: "-probeOnly").map { Set($0.split(separator: ",").map { $0.lowercased() }) },
                stressCalls: flags.contains("-probeStress") ? value(after: "-probeStressN").flatMap(Int.init) ?? 20 : nil)
        }
        if let route = value(after: "-KokoroStress").flatMap({ KokoroStressRun.Route(rawValue: $0.lowercased()) }) {
            kokoroStress = KokoroStressRun.Request(
                route: route,
                calls: value(after: "-KokoroStressCalls").flatMap(Int.init).map { max(1, $0) } ?? KokoroStressCorpus.calls,
                fresh: flags.contains("-KokoroStressFresh"),
                coreMLUnits: kokoroUnits)
        }
    }

    /// Whether the app reopens on the surface it was left on.
    var restoresSurface: Bool { !uiTesting || restoresSurfaceInUITests }

    /// Live Google suggestions in the address field.
    var fetchesSuggestions: Bool { !uiTesting }
}
#endif
