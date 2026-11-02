#if DEBUG
import Foundation

/// Launch arguments, parsed once (Debug builds only). Probes of the running app, screenshot
/// runs and diagnostics drive the app through these (state seeding, fixtures, accessibility markers; no test target depends on them); a normal launch has none of them.
struct LaunchOptions: Equatable {
    /// `-seedDemoArticle`: one deterministic demo article.
    struct DemoArticle: Equatable {
        /// `-seedDemoPlainText`: the article has no HTML, only its plain text.
        var plainTextOnly = false
        /// `-seedPlayedPages N`: also N pages played without saving, part-way ("Played Page 1"
        /// played most recently): the Library's Recent tab.
        var playedArticles = 0
        /// `-seedDemoParagraphs N`: the article runs to N paragraphs (the first three as always, the rest
        /// "Paragraph 4: ..." ... one sentence each), so there is text to scroll away from the audio.
        var paragraphs = 3
        /// `-seedDemoListenAt P`: the article's saved listening spot is paragraph P (0 = the start).
        var listenAt = 0
    }

    /// `-uiTesting`: expose test-only accessibility markers and skip network-dependent features
    /// (live search suggestions), so results don't depend on the network.
    var uiTesting = false
    /// `-stubSuggestions` (with `-uiTesting`): the address field's live suggestions are fixed rows
    /// (`SearchSuggestionProvider.stub`) rather than none.
    var stubsSuggestions = false
    /// `-resetLibrary`: start as a fresh install does. Before anything reads them, the stored
    /// settings go (every owner's `storedKeys`: the engine, the voices and each voice library's own
    /// settings, language and speed, both appearances, the remembered surface and the Library's tab
    /// and sort, Recent Searches, Block Ads, developer options and Listen Debug) with the prepare list (`LaunchHooks.resetStoredSettings`). Before the seeds, the
    /// library's every page (link pages too) and folder go, with their audio, and the browsing
    /// history (`LaunchHooks.resetLibrary`). The seeds then add to an empty library. Every UI
    /// test launches with it.
    var resetsLibrary = false
    var demoArticle: DemoArticle?
    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): start in the Browser's reader mode on it (compact
    /// width; the Reader sheet on regular width), over page one with `-browseTestPages`.
    var opensDemoInReader = false
    /// `-readDemoInLibrary` (with `-seedDemoArticle`): start in Library Read on it (the Reader sheet on regular width).
    var readsDemoInLibrary = false
    /// `-switchDestinationAndBack library|settings`: 5 s after launch, what a tap on that pill segment
    /// does, then 2 s later the Browser's segment, to check the Browser comes back as it was left.
    var switchesDestinationAndBack: String?
    /// `-openLibrary`: start in the library.
    var opensLibrary = false
    /// `-openLibraryFolder <name>`: once launched, the Library on the first folder named `<name>`
    /// (`-seedDemoFolders`' "Demo Finance"), as a tap on its row does.
    var opensLibraryFolder: String?
    /// `-openSettings`: once launched, what a tap on the pill's Settings does. `-searchSettings <text>`:
    /// then Search Settings holds the text. `-openSettingsPage <page>` (`voice`, `appearance`, …): then
    /// that page is pushed.
    var opensSettings = false
    var settingsSearch: String?
    var settingsPage: SettingsRoute?
    /// `-browseTestPages`: serve and open the offline `reader-test://` pages.
    var servesTestPages = false
    /// `-testStoryChapters N`: the offline story's table of contents (`reader-test://story/toc`)
    /// lists N chapters (8 without it), so a check finds new ones on a later launch.
    var testStoryChapters = 8
    /// `-testStoryThrottles`: the offline story's chapter 6 doesn't load the first time it is
    /// asked for in a launch (a site not answering), for Follow's back-off.
    var testStoryThrottles = false
    /// `-seedHistory`: visited `example.com` pages in the browser's History (one untitled), three
    /// sites' worth for the start page's Frequently Visited.
    var seedsHistory = false
    /// `-bakeArticle <id prefix>`: render that saved article's audio top-down without playing.
    var bakeArticlePrefix: String?
    /// `-scrubBubbleDemo` (with `-uiTesting`): freeze a mid-drag scrubber frame for a screenshot.
    var scrubBubbleDemo = false
    /// `-slowMenuAnimation`: slow the ⋯ morph so a mid-animation frame can be captured.
    var slowMenuAnimation = false
    /// `-chromeFallback`: draw the compact bottom chrome in its pre-iOS 26 skin (the blur and
    /// glass tint) on a new OS, since no older simulator runtime is installed to look at it.
    var forcesChromeFallback = false
    /// `-chromeFold P`: hold the compact chrome's fold at P (0.5 one row, 1 the bubble) wherever it may fold,
    /// to look at a folded form without a finger on the screen.
    var chromeFold: CGFloat?
    /// `-readerFullScreen`: the first reading page shown (in place: `-openDemoInBrowseReader`,
    /// `-readDemoInLibrary`; or Listen: `-listenDemo`) goes full screen once it is up
    /// (`ReadingChrome.opensInFullScreen`).
    var readerFullScreen = false
    /// `-readerScrollToEnd`: the first reading page shown goes to the end of its text, as a finger would
    /// (`HTMLReadingWebView.Coordinator.scrollsToEndOnOpen`).
    var readerScrollsToEnd = false
    /// `-readerProbe STEPS`: the first reading page shown runs these steps once it has loaded and laid
    /// out, logging `ReaderProbe step=… fullScreen=… offset=…` after each (`ReaderProbeStep.parse`:
    /// `a` anchor, `dN` / `uN` N pt down / up, `pN` a pull to -N, `rN` a rebound to N, `c` the centre tap).
    var readerProbe: [ReaderProbeStep]?
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
    /// does (decision D10). Without it an `-uiTesting` launch starts on the browser, whatever an earlier
    /// run left, and `-browseTestPages` loads page one.
    var restoresSurfaceInUITests = false
    /// `-importTestEPUB`: *Import Book…* imports the synthetic EPUB (`TestEPUB`) instead of
    /// opening the Files picker, which a probe can't drive.
    var importsTestEPUB = false
    /// `-playTestEPUB`: at launch, import the synthetic EPUB into the Library's top level (no
    /// sheet), then play it from its place, as a book's Play does.
    var playsTestEPUB = false
    /// `-listenDemo`: once launched, Listen to the newest saved page and raise Listen over the surface
    /// on screen. `-listenDemoFrom <address or folder name>`: first open that page (scrolled down
    /// 300 pt) or that Library folder. `-closeListenAfter N`: N seconds later, Listen closes, back
    /// to that surface.
    var listensDemo = false
    /// `-tapListen`: once launched, what a tap on the chrome's Listen does (with `-closeListenAfter`, then closes).
    var tapsListen = false
    /// `-tapListenWhen fullScreen`: the same once an in-place reader is in full screen (polled every
    /// 100 ms, up to 10 s), in place of `-tapListen`'s fixed second.
    var tapsListenWhenFullScreen = false
    /// `-tapLibraryRow <title>`: once launched, what a tap on the Library row of the first page whose
    /// title starts with `<title>` does (`LibraryActions.tap`), from the Library.
    var tapsLibraryRow: String?
    /// `-pasteText <text>`: once launched, *Paste Text…*'s *Save* of `<text>` into the top level.
    var pastesText: String?
    /// `-importBook`: once launched, what *Import from…* does (with `-importTestEPUB`, the test book).
    var importsBook = false
    var listenDemoFrom: String?
    var closesListenAfter: Double?
    /// `-failLibrarySaves`: once the launch work is done (seeds, maintenance), every
    /// library save fails, so a probe sees the edits that can't be saved.
    var failsLibrarySaves = false
    /// `-testVoice`: register an offline on-device test voice (`TestVoiceProvider`, "Test Voice"
    /// with voices One and Two); `-selectEngine test.voice` picks it. Downloads render with it.
    var usesTestVoice = false
    /// `-showWhatsNew`: show the What's New sheet even under `-uiTesting`.
    var showsWhatsNew = false
    /// `-simulateVoiceDownloads`: Kokoro's downloads and removals in the Voice picker run offline
    /// (`KokoroDownloadSimulation`): `-voiceDownloadSeconds N` (8) to fill, `-failVoiceDownload
    /// <voice ids, comma separated>` fail half-way, `-kokoroNotDownloaded` starts with its model missing,
    /// `-transferVoice <voice id>` starts a download of it outside the picker (as playback's load would).
    var voiceDownloadSimulation: VoiceDownloadSimulationOptions?
    struct VoiceDownloadSimulationOptions: Equatable {
        let seconds: Double
        let failing: Set<String>
        let modelMissing: Bool
        let playbackTransfer: String?
    }
    /// `-downloadVoice <voice id>` (with `-openSettingsPage voice`): two seconds in, what a tap on
    /// that voice's row in Settings › Voice does; `-stopVoiceDownloadAfter N` then stops it N s later.
    var downloadsVoice: String?
    var stopsVoiceDownloadAfter: Double?
    /// `-editVoices`: Settings › Voice opens in Edit. `-removeVoice <voice id>`: a second after it
    /// opens, what that voice's *Remove* does (its question, when it asks).
    var editsVoices = false
    var removesVoice: String?
    /// `-openVoiceSection <engine>` ("kokoro", or its id): the voice pickers open with that
    /// engine's section open, as well as the ones they open anyway.
    var opensVoiceSection: String?
    /// `-revealVoiceRemove <voice id>` (with `-editVoices`): that row's *Remove* shows, as after
    /// a tap on its ⊖.
    var revealsVoiceRemove: String?
    /// `-openVoicePicker`: the newest saved article's *Voice* sheet; with `-seedDemoBook`, the book's.
    var opensVoicePicker = false
    /// `-selectEngine <engine id>` (`local.phonon`, `local.kokoro`, `test.voice`): the engine to
    /// load at launch; its voice is the default for new articles.
    var selectsEngine: SpeechEngineID?
    /// `-renderPolicy lanes`: render on two lanes in front (`LanePolicy`) instead of the app's
    /// one call at a time on the CPU (`SingleCallPolicy`).
    var usesLanePolicy = false
    /// `-engineProbe [-probeOnly Kokoro,…] [-probeStress [-probeStressN n]]`: time every on-device
    /// engine once launched (`EngineLatencyProbe`).
    var engineProbe: EngineLatencyProbe.Request?
    /// `-KokoroStress [-KokoroStressCalls n] [-KokoroStressFresh]`: the Kokoro crash
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
        stubsSuggestions = uiTesting && flags.contains("-stubSuggestions")
        resetsLibrary = flags.contains("-resetLibrary")
        if flags.contains("-seedDemoArticle") {
            demoArticle = DemoArticle(plainTextOnly: flags.contains("-seedDemoPlainText"),
                                      playedArticles: value(after: "-seedPlayedPages").flatMap(Int.init) ?? 0,
                                      paragraphs: value(after: "-seedDemoParagraphs").flatMap(Int.init) ?? 3,
                                      listenAt: value(after: "-seedDemoListenAt").flatMap(Int.init) ?? 0)
        }
        opensDemoInReader = flags.contains("-openDemoInBrowseReader")
        readsDemoInLibrary = flags.contains("-readDemoInLibrary")
        switchesDestinationAndBack = value(after: "-switchDestinationAndBack")
        opensLibrary = flags.contains("-openLibrary")
        opensLibraryFolder = value(after: "-openLibraryFolder")
        settingsSearch = value(after: "-searchSettings")
        settingsPage = value(after: "-openSettingsPage").flatMap(SettingsRoute.init(rawValue:))
        opensSettings = flags.contains("-openSettings") || settingsSearch != nil || settingsPage != nil
        servesTestPages = flags.contains("-browseTestPages")
        testStoryChapters = value(after: "-testStoryChapters").flatMap(Int.init) ?? testStoryChapters
        testStoryThrottles = flags.contains("-testStoryThrottles")
        seedsHistory = flags.contains("-seedHistory")
        bakeArticlePrefix = value(after: "-bakeArticle")?.uppercased()
        scrubBubbleDemo = uiTesting && flags.contains("-scrubBubbleDemo")
        slowMenuAnimation = flags.contains("-slowMenuAnimation")
        forcesChromeFallback = flags.contains("-chromeFallback")
        readerFullScreen = flags.contains("-readerFullScreen")
        readerScrollsToEnd = flags.contains("-readerScrollToEnd")
        readerProbe = value(after: "-readerProbe").flatMap(ReaderProbeStep.parse)
        chromeFold = value(after: "-chromeFold").flatMap(Double.init).map { CGFloat($0) }
        rerunsLibraryMigration = flags.contains("-rerunLibraryMigration")
        seedsDemoBook = flags.contains("-seedDemoBook")
        demoBookPlace = value(after: "-seedDemoBookPlace").flatMap(Int.init)
        chainsDemoChapters = flags.contains("-chainDemoChapters")
        seedsDemoFolders = flags.contains("-seedDemoFolders")
        bigFolderArticles = value(after: "-seedBigFolder").flatMap(Int.init) ?? 0
        restoresSurfaceInUITests = flags.contains("-restoreSurface")
        importsTestEPUB = flags.contains("-importTestEPUB")
        playsTestEPUB = flags.contains("-playTestEPUB")
        listensDemo = flags.contains("-listenDemo")
        tapsListen = flags.contains("-tapListen")
        tapsListenWhenFullScreen = value(after: "-tapListenWhen") == "fullScreen"
        tapsLibraryRow = value(after: "-tapLibraryRow")
        pastesText = value(after: "-pasteText")
        importsBook = flags.contains("-importBook")
        listenDemoFrom = value(after: "-listenDemoFrom")
        closesListenAfter = value(after: "-closeListenAfter").flatMap(Double.init)
        failsLibrarySaves = flags.contains("-failLibrarySaves")
        showsWhatsNew = flags.contains("-showWhatsNew")
        usesTestVoice = flags.contains("-testVoice")
        selectsEngine = value(after: "-selectEngine").map(SpeechEngineID.init(rawValue:))
        if flags.contains("-simulateVoiceDownloads") {
            voiceDownloadSimulation = VoiceDownloadSimulationOptions(seconds: value(after: "-voiceDownloadSeconds").flatMap(Double.init) ?? 8,
                                       failing: Set((value(after: "-failVoiceDownload") ?? "").split(separator: ",").map(String.init)),
                                       modelMissing: flags.contains("-kokoroNotDownloaded"),
                                       playbackTransfer: value(after: "-transferVoice"))
        }
        downloadsVoice = value(after: "-downloadVoice")
        stopsVoiceDownloadAfter = value(after: "-stopVoiceDownloadAfter").flatMap(Double.init)
        editsVoices = flags.contains("-editVoices")
        removesVoice = value(after: "-removeVoice")
        opensVoiceSection = value(after: "-openVoiceSection")
        revealsVoiceRemove = value(after: "-revealVoiceRemove")
        opensVoicePicker = flags.contains("-openVoicePicker")
        usesLanePolicy = value(after: "-renderPolicy") == "lanes"
        if flags.contains("-engineProbe") {
            engineProbe = EngineLatencyProbe.Request(
                engines: value(after: "-probeOnly").map { Set($0.split(separator: ",").map { $0.lowercased() }) },
                stressCalls: flags.contains("-probeStress") ? value(after: "-probeStressN").flatMap(Int.init) ?? 20 : nil)
        }
        if flags.contains("-KokoroStress") {
            kokoroStress = KokoroStressRun.Request(
                calls: value(after: "-KokoroStressCalls").flatMap(Int.init).map { max(1, $0) } ?? KokoroStressCorpus.calls,
                fresh: flags.contains("-KokoroStressFresh"))
        }
    }

    /// Whether the app reopens on the surface it was left on.
    var restoresSurface: Bool { !uiTesting || restoresSurfaceInUITests }

    /// Where the address field's live suggestions come from.
    var suggestionProvider: SearchSuggestionProvider { uiTesting ? (stubsSuggestions ? .stub : .none) : .live }
}
#endif
