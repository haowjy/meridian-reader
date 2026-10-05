#if DEBUG
import Foundation
import SwiftData

/// What the UI-test and diagnostics launch arguments (`LaunchOptions`) do (Debug builds only). A
/// normal launch runs none of this.
@MainActor
enum LaunchHooks {
    /// Before the library's launch maintenance: the engine probe, and `-rerunLibraryMigration`.
    static func runBeforeMigrations(_ options: LaunchOptions, library: LibraryStore, tts: LocalTTSCoordinator) {
        EngineLatencyProbe.runIfRequested(coordinator: tts)
        if options.rerunsLibraryMigration { library.resetForMigrationRerun() }
    }

    /// After the migration copy, before the layout pass: the demo seeds.
    static func runSeeds(_ options: LaunchOptions, library: LibraryStore) {
        if let demo = options.demoArticle { seedDemoArticle(demo, in: library) }
        if options.seedsDemoBook { seedDemoBook(in: library) }
    }

    /// After the migrations, before crash resume: bake, bookmarks, and where the app starts.
    static func runAfterMigrations(_ options: LaunchOptions, library: LibraryStore, speech: SpeechController,
                                   shell: ShellState) {
        if let prefix = options.bakeArticlePrefix { bakeArticle(prefix: prefix, in: library, speech: speech) }
        if let setup = options.bookmarks { setUpBookmarks(setup, in: library) }
        if options.servesTestPages, let url = URL(string: "reader-test://pages/one") { shell.navigate(to: url) }
        if options.opensLibrary { shell.openLibrary() }
        if options.opensDemoInReader { openNewestInReader(in: library, shell: shell) }
    }

    /// Last, after crash resume (which wins): `-importTestEPUB`, `-playTestEPUB`, `-chainDemoChapters`.
    static func runAfterLaunch(_ options: LaunchOptions, library: LibraryStore, speech: SpeechController) async {
        if options.importsTestEPUB { await importTestEPUB(in: library) }
        if options.playsTestEPUB { await playTestEPUB(library: library, speech: speech) }
        if options.chainsDemoChapters { await chainDemoChapters(library: library, speech: speech) }
    }

    /// `-importTestEPUB`: the synthetic EPUB, written to a temporary file and imported into the top
    /// level through `BookImporter`. An earlier launch's import of it is deleted first, with its
    /// audio, so the book starts unplayed. Logged as `debug_import_test_epub`.
    @discardableResult
    static func importTestEPUB(in library: LibraryStore) async -> Folder? {
        if let earlier = library.book(key: TestEPUB.bookKey) { try? library.deleteFolder(earlier, keepContents: false) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-book.epub")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try TestEPUB.write(to: file)
            let outcome = try await BookImporter(library: library).importBook(at: file, into: nil, ifAlreadyInLibrary: .cancel)
            guard case .added(let book) = outcome else { return nil }
            ListenTimingLog.log("debug_import_test_epub", ["ok": true, "chapters": library.playOrder(of: book).count], console: true)
            return book
        } catch {
            ListenTimingLog.log("debug_import_test_epub", ["ok": false, "error": "\(error)"], console: true)
            return nil
        }
    }

    /// `-playTestEPUB`: the imported test book plays from its place (chapter 1 the first time).
    static func playTestEPUB(library: LibraryStore, speech: SpeechController) async {
        guard let book = library.book(key: TestEPUB.bookKey), let start = await play(book, library: library, speech: speech) else {
            ListenTimingLog.log("debug_play_test_epub", ["started": false], console: true)
            return
        }
        ListenTimingLog.log("debug_play_test_epub", ["started": true, "title": start.page.title], console: true)
    }

    /// `-seedDemoBook`: the demo book (a skipped title page and three chapters) and one page in no
    /// folder, replacing the ones an earlier launch seeded, with their audio. Fresh keys each
    /// launch, so no audio rendered before carries over. It runs on a phone with real data (the
    /// chapter-boundary device check), so it removes only rows it marked itself: the book by its
    /// `sourceIdentifier`, with its chapters (no page can be moved into a book), and the page in
    /// no folder by `DemoBook.loosePageMarker`. An address another page already has isn't given
    /// to a seeded page, since the launch's dedupe would merge the two: that chapter goes without
    /// it, and the page in no folder isn't added.
    static func seedDemoBook(in library: LibraryStore) {
        for folder in demoBooks(in: library) { try? library.deleteFolder(folder, keepContents: false) }
        for page in seededLoosePages(in: library) { library.delete(page) }
        let book = Folder(name: DemoBook.title, kind: .book, sortKey: library.nextFolderSortKey(in: nil))
        book.byline = DemoBook.author
        book.sourceIdentifier = DemoBook.sourceIdentifier
        library.context.insert(book)
        for (index, chapter) in DemoBook.chapters.enumerated() {
            let url = DemoBook.url(ofChapter: index)
            let page = demoPage(chapter, url: library.page(url: url) == nil ? url : nil, sortKey: Double(index))
            page.locator = "chapter-\(index).xhtml"
            page.skipsInPlayback = chapter.skipsInPlayback
            library.context.insert(page)
            page.setFolder(book)
        }
        if library.page(url: DemoBook.loosePageURL) == nil {
            let loose = demoPage(DemoBook.loosePage, url: DemoBook.loosePageURL, sortKey: library.nextSortKey(in: nil))
            loose.locator = DemoBook.loosePageMarker
            library.context.insert(loose)
        } else {
            library.log("demo seed: \(DemoBook.loosePageURL.absoluteString) is another page's; no page in no folder added")
        }
        library.commit("demo book seed")
    }

    /// The demo book an earlier seed added, wherever it was moved.
    private static func demoBooks(in library: LibraryStore) -> [Folder] {
        let source: String? = DemoBook.sourceIdentifier
        return (try? library.context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.sourceIdentifier == source }))) ?? []
    }

    /// The page in no folder an earlier seed added, by its marker.
    private static func seededLoosePages(in library: LibraryStore) -> [Page] {
        let marker: String? = DemoBook.loosePageMarker
        return (try? library.context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.locator == marker }))) ?? []
    }

    private static func demoPage(_ chapter: DemoBook.Chapter, url: URL?, sortKey: Double) -> Page {
        let page = Page(key: UUID(), title: chapter.title, byline: DemoBook.author, urlString: url?.absoluteString,
                        contentState: .saved, addedAt: .now, sortKey: sortKey)
        page.cleanedHTML = chapter.html
        page.plainText = chapter.plainText
        page.excerpt = String(chapter.plainText.prefix(140))
        page.wordCount = SavedArticle.wordCount(of: chapter.plainText)
        return page
    }

    /// `-chainDemoChapters`: plays the demo book from where Continue would (chapter 1 the first
    /// time), after waiting (≤ 20 s) for the on-device engine so it doesn't start on Apple. Logged
    /// as `debug_chain_demo_chapters`; each boundary then logs `chapter_boundary`.
    static func chainDemoChapters(library: LibraryStore, speech: SpeechController) async {
        guard let book = demoBooks(in: library).first, let start = await play(book, library: library, speech: speech) else {
            ListenTimingLog.log("debug_chain_demo_chapters", ["started": false], console: true)
            return
        }
        ListenTimingLog.log("debug_chain_demo_chapters", [
            "started": true, "key": ListenTimingLog.shortKey(start.page.listenKey), "p": start.paragraph,
            "engine": speech.activeEngine?.name ?? "—", "build": LocalTTSCoordinator.buildConfiguration,
        ], console: true)
    }

    /// Plays `book` from where Continue would, unless something already plays, after waiting
    /// (≤ 20 s) for the on-device engine so it doesn't start on Apple. Returns where it started.
    private static func play(_ book: Folder, library: LibraryStore, speech: SpeechController) async -> (page: Page, paragraph: Int)? {
        guard speech.activeSessionID == nil, let start = library.continueStart(of: book) else { return nil }
        let tts = speech.localTTS
        var waited = 0
        while tts.synth.state.warmingEngineID != nil, waited < 100 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        speech.toggle(.page(start.page), resumeParagraph: start.paragraph, resumeUTF16Offset: start.utf16Offset)
        return (start.page, start.paragraph)
    }

    /// `-seedDemoArticle`: replace the saved and played pages with one deterministic article, so
    /// a stored resume position can't stick at the end between tests (and, with
    /// `-seedPlayedPages N`, N pages played without saving). Favorites' links stay
    /// (`-resetBookmarks` / `-seedBookmarks` handle them).
    static func seedDemoArticle(_ demo: LaunchOptions.DemoArticle, in library: LibraryStore) {
        let context = library.context
        for page in (try? context.fetch(FetchDescriptor<Page>())) ?? [] where !page.isLink {
            context.delete(page)
        }
        let plain = """
        First paragraph for listen probe. This one is intentionally longer so Simulator UI tests can press next and previous before speech finishes the whole article on its own.

        Second paragraph so next and previous skip have somewhere to go. Extra sentences keep the synthesizer busy while the probe checks speed and paragraph controls.

        Third paragraph finishes the demo article used by Simulator UI tests. One more cushion of text so stop can be exercised while playback is still active.
        """
        let html = """
        <p>First paragraph for listen probe. This one is intentionally longer so Simulator UI tests can press next and previous before speech finishes the whole article on its own.</p>
        <p>Second paragraph so next and previous skip have somewhere to go. Extra sentences keep the synthesizer busy while the probe checks speed and paragraph controls.</p>
        <p>Third paragraph finishes the demo article used by Simulator UI tests. One more cushion of text so stop can be exercised while playback is still active.</p>
        """
        let extras = (3..<demo.paragraphs).map { i in
            "Extra paragraph \(i + 1) keeps the demo going while the app is in the background. "
                + "It talks about harbor \(i + 1), where boats come and go, and the weather changes every hour."
        }
        let plainAll = ([plain] + extras).joined(separator: "\n\n")
        let htmlAll = ([html] + extras.map { "<p>\($0)</p>" }).joined(separator: "\n")
        // A fresh key each launch, so no audio rendered by an earlier test carries over.
        let page = Page(key: UUID(), title: demo.title ?? "Demo Listen Article", byline: "example.com",
                        urlString: "https://example.com/demo", contentState: .saved, addedAt: .now,
                        sortKey: library.nextSortKey(in: nil))
        page.cleanedHTML = demo.plainTextOnly ? "" : htmlAll
        page.plainText = plainAll
        page.excerpt = String(plain.prefix(140))
        page.wordCount = SavedArticle.wordCount(of: plainAll)
        page.positionParagraph = demo.progress
        context.insert(page)
        for i in 0..<demo.playedPages {
            let text = ["Played page \(i + 1), first paragraph.", "Played page \(i + 1), second paragraph."]
            let played = Page(key: UUID(), title: "Played Page \(i + 1)", byline: "example.com",
                              urlString: "https://example.com/played-\(i + 1)", contentState: .saved, addedAt: nil)
            played.cleanedHTML = text.map { "<p>\($0)</p>" }.joined()
            played.plainText = text.joined(separator: "\n\n")
            played.storeListenParagraphs(text)
            played.lastPlayedAt = Date.now.addingTimeInterval(-60 * Double(i + 1))
            context.insert(played)
        }
        library.commit("demo seed")
    }

    /// `-bakeArticle <id prefix>` (e.g. `xcrun devicectl device process launch …
    /// com.jimmyyao.Reader -bakeArticle 0C25B7EE`): render a saved article's audio top-down
    /// without playing it, then read ListenTiming / TTSCache.
    static func bakeArticle(prefix: String, in library: LibraryStore, speech: SpeechController) {
        let pages = (try? library.context.fetch(FetchDescriptor<Page>())) ?? []
        guard let page = pages.first(where: { $0.hasText && $0.listenKey.uuidString.hasPrefix(prefix) }) else {
            ListenTimingLog.log("debug_bake_article", ["prefix": prefix, "found": false])
            return
        }
        let paragraphs = page.listenDocument().paragraphs
        ListenTimingLog.log("debug_bake_article", [
            "prefix": prefix, "found": true, "key": ListenTimingLog.shortKey(page.listenKey), "paragraphs": paragraphs.count,
        ])
        speech.localTTS.startBakeIfNeeded(articleID: page.listenKey, paragraphs: paragraphs, voiceID: speech.cacheVoiceID)
    }

    /// `-resetBookmarks` / `-seedBookmarks`: Favorites emptied (saved pages in it go back to the
    /// pages in no folder), then optionally seeded.
    static func setUpBookmarks(_ setup: LaunchOptions.BookmarkSetup, in library: LibraryStore) {
        for page in library.favoritePages() { library.removeFavorite(page) }
        guard setup == .seed else { return }
        let seeds = [
            ("https://www.gutenberg.org/", "Project Gutenberg"),
            ("https://en.wikipedia.org/wiki/Speech_synthesis", "Speech synthesis"),
            ("https://news.ycombinator.com/", "Hacker News"),
            ("https://www.theverge.com/", "The Verge"),
            ("https://example.com/", "Example"),
        ]
        for (url, title) in seeds {
            if let url = URL(string: url) { library.addFavorite(url: url, title: title, artwork: nil) }
        }
    }

    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): the newest saved article in the Reader
    /// sheet over the browser, without needing the network.
    static func openNewestInReader(in library: LibraryStore, shell: ShellState) {
        var newest = LibraryQueries.savedInLibrary
        newest.fetchLimit = 1
        guard let page = try? library.context.fetch(newest).first else { return }
        var article = ReaderArticle(page: page)
        if article.document.isEmpty {
            let document = Page.buildListenDocument(plainText: page.plainText, cleanedHTML: page.cleanedHTML,
                                                    title: page.title)
            article.document = document
            article.trustedParagraphs = document.paragraphs
        }
        shell.openReader(article)
    }
}
#endif
