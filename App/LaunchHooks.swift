#if DEBUG
import Foundation
import SwiftData

/// What the UI-test and diagnostics launch arguments (`LaunchOptions`) do (Debug builds only). A
/// normal launch runs none of this.
@MainActor
enum LaunchHooks {
    /// Before the library's launch maintenance: the engine probe, the Kokoro stress run, and
    /// `-rerunLibraryMigration`.
    static func runBeforeMigrations(_ options: LaunchOptions, library: LibraryStore, tts: LocalTTSCoordinator) {
        if let probe = options.engineProbe { EngineLatencyProbe.start(probe, coordinator: tts) }
        if let stress = options.kokoroStress { KokoroStressRun.start(stress, coordinator: tts) }
        if options.rerunsLibraryMigration { library.resetForMigrationRerun() }
    }

    /// `-resetLibrary`'s stored settings, before anything reads them (`AppMain`): every key the
    /// settings' owners store (each names its own, `storedKeys`), and the download list. Launch
    /// arguments (`-reading.theme sepia`) still apply over what is cleared.
    static func resetStoredSettings(engines: EngineRegistry, defaults: UserDefaults = .standard,
                                    downloads: DownloadListStore = DownloadListStore()) {
        let keys = SpeechController.storedKeys + LocalTTSCoordinator.storedKeys(for: engines)
            + AppAppearance.storedKeys + ReadingAppearance.storedKeys + LibraryTopLevel.storedKeys
            + RecentSearches.storedKeys + ContentBlocker.storedKeys + SurfaceMemoryStore.storedKeys
        for key in keys { defaults.removeObject(forKey: key) }
        downloads.save([])
    }

    /// After the migration copy, before the layout pass: `-resetLibrary`, then the demo seeds,
    /// which add to what is left.
    static func runSeeds(_ options: LaunchOptions, library: LibraryStore) {
        if options.resetsLibrary { resetLibrary(library) }
        if let demo = options.demoArticle { seedDemoArticle(demo, in: library) }
        if options.seedsDemoBook { seedDemoBook(in: library, place: options.demoBookPlace) }
        if options.seedsDemoFolders { seedDemoFolders(in: library) }
    }

    /// `-resetLibrary`: every page (link pages too) and every folder goes, each page's audio,
    /// queued renders and bake job with it (as a delete does), and the browsing history.
    static func resetLibrary(_ library: LibraryStore) {
        let context = library.context
        _ = try? library.edit("reset library") {
            for page in (try? context.fetch(FetchDescriptor<Page>())) ?? [] { library.deleteWithoutSaving(page) }
            for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] { context.delete(folder) }
            for visit in (try? context.fetch(FetchDescriptor<RecentVisit>())) ?? [] { context.delete(visit) }
        }
    }

    /// `-seedDemoFolders`: "Demo Finance" with the subfolders "Bonds" (holding "Coupon Basics") and
    /// "Taxes", and three saved pages of its own, one part-way and one finished. Synthetic text,
    /// `example.com` addresses.
    static func seedDemoFolders(in library: LibraryStore) {
        guard let finance = try? library.makeFolder(name: "Demo Finance", in: nil),
              let bonds = try? library.makeFolder(name: "Bonds", in: finance),
              (try? library.makeFolder(name: "Taxes", in: finance)) != nil else { return }
        func page(_ title: String, slug: String, in folder: Folder, sortKey: Double) -> Page {
            let paragraphs = (1...6).map { "\(title), paragraph \($0). A synthetic note about saving, yields and the plain arithmetic of interest over a few years." }
            let page = Page(key: UUID(), title: title, byline: "investing.example.com",
                            urlString: "https://investing.example.com/\(slug)-\(UUID().uuidString.prefix(6))",
                            contentState: .saved, addedAt: .now, sortKey: sortKey)
            page.setText(html: paragraphs.map { "<p>\($0)</p>" }.joined(), plain: paragraphs.joined(separator: "\n\n"),
                         excerpt: paragraphs[0], paragraphs: paragraphs)
            library.context.insert(page)
            page.setFolder(folder)
            return page
        }
        _ = page("Coupon Basics", slug: "coupons", in: bonds, sortKey: 0)
        let yield = page("Seven-Day Yield", slug: "yield", in: finance, sortKey: 0)
        yield.positionParagraph = 3
        yield.lastPlayedAt = .now.addingTimeInterval(-3600)
        let funds = page("Money Market Funds", slug: "funds", in: finance, sortKey: 1)
        funds.finishedAt = .now.addingTimeInterval(-7200)
        _ = page("Index Funds", slug: "index", in: finance, sortKey: 2)
        library.commit("demo folders seed")
    }

    /// After the migrations, before crash resume: bake, bookmarks, and where the app starts.
    static func runAfterMigrations(_ options: LaunchOptions, library: LibraryStore, speech: SpeechController,
                                   shell: ShellState) {
        if let prefix = options.bakeArticlePrefix { bakeArticle(prefix: prefix, in: library, speech: speech) }
        if options.seedsBookmarks { seedBookmarks(in: library) }
        if options.servesTestPages, !options.restoresSurface, let url = URL(string: "reader-test://pages/one") {
            shell.navigate(to: url)
        }
        if options.opensLibrary { shell.openLibrary() }
        if options.opensDemoInReader { openNewestInReader(in: library, shell: shell) }
        if options.failsLibrarySaves { library.saveContext = { _ in throw InjectedSaveFailure() } }
    }

    /// `-failLibrarySaves`' refusal.
    private struct InjectedSaveFailure: Error {}

    /// Last, after crash resume (which wins): `-playTestEPUB`, `-chainDemoChapters`.
    static func runAfterLaunch(_ options: LaunchOptions, library: LibraryStore, speech: SpeechController) async {
        if options.playsTestEPUB {
            await importTestEPUB(in: library)
            await playTestEPUB(library: library, speech: speech)
        }
        if options.chainsDemoChapters { await chainDemoChapters(library: library, speech: speech) }
    }

    /// `-playTestEPUB`: the synthetic EPUB, written to a temporary file and imported into the top
    /// level through `BookImporter` (no sheet). An earlier launch's import of it is deleted first,
    /// with its audio, so the book starts unplayed. Logged as `debug_import_test_epub`.
    @discardableResult
    static func importTestEPUB(in library: LibraryStore) async -> Folder? {
        if let earlier = library.book(key: TestEPUB.bookKey) { try? library.deleteFolder(earlier) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-book.epub")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try TestEPUB.write(to: file)
            let outcome = try await BookImporter(library: library).importBook(at: file, into: nil, ifAlreadyInLibrary: .cancel)
            guard case .added(let book) = outcome else { return nil }
            ListenTimingLog.log("debug_import_test_epub", ["ok": true, "chapters": library.pages(in: book).count], console: true)
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
    /// `sourceIdentifier` and its chapters by the book's record (`BookSourceState.chapterKeys`),
    /// wherever they were moved (anything moved into the book moves up out of it), and the page
    /// in no folder by `DemoBook.loosePageMarker`. An address another page already has isn't given
    /// to a seeded page, since the launch's dedupe would merge the two: that chapter goes without
    /// it, and the page in no folder isn't added.
    /// `place`: the book is part-way, at that chapter's third paragraph (`-seedDemoBookPlace`).
    static func seedDemoBook(in library: LibraryStore, place: Int? = nil) {
        for folder in demoBooks(in: library) {
            for page in (folder.bookState?.chapterKeys ?? []).compactMap(library.page(key:)) { library.delete(page) }
            let strays = library.subfolders(of: folder).map(LibraryItem.folder) + library.pages(in: folder).map(LibraryItem.page)
            try? library.move(strays, to: folder.parent)
            try? library.deleteFolder(folder)
        }
        for page in seededLoosePages(in: library) { library.delete(page) }
        let book = Folder(name: DemoBook.title, kind: .book, sortKey: library.nextFolderSortKey(in: nil))
        book.byline = DemoBook.author
        book.sourceIdentifier = DemoBook.sourceIdentifier
        library.context.insert(book)
        var chapterKeys: [UUID] = []
        for (index, chapter) in DemoBook.chapters.enumerated() {
            let url = DemoBook.url(ofChapter: index)
            let page = demoPage(chapter, url: library.page(url: url) == nil ? url : nil, sortKey: Double(index))
            page.locator = "chapter-\(index).xhtml"
            page.skipsInPlayback = chapter.skipsInPlayback
            library.context.insert(page)
            page.setFolder(book)
            chapterKeys.append(page.listenKey)
            if let place, DemoBook.chapters.indices.contains(place) {
                if index > 0 && index < place { page.finishedAt = .now.addingTimeInterval(-3600) }
                if index == place {
                    page.positionParagraph = 2
                    page.lastPlayedAt = .now.addingTimeInterval(-600)
                    book.currentPageKey = page.key
                }
            }
        }
        book.sourceStateData = try? JSONEncoder().encode(BookSourceState(chapterKeys: chapterKeys))
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
        seedText(page, html: chapter.html, plain: chapter.plainText)
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
            "started": true, "key": ListenTimingLog.shortKey(start.page.listenKey), "p": start.spot.paragraph,
            "engine": speech.activeEngine?.name ?? "—", "build": LocalTTSCoordinator.buildConfiguration,
        ], console: true)
    }

    /// Plays `book` from where Continue would, unless something already plays, after waiting
    /// (≤ 20 s) for the on-device engine so it doesn't start on Apple. Returns where it started.
    private static func play(_ book: Folder, library: LibraryStore, speech: SpeechController) async -> (page: Page, spot: ListenSpot)? {
        guard speech.activeSessionID == nil, let start = library.continueStart(of: book) else { return nil }
        await speech.localTTS.waitForEngineLoad(timeout: .seconds(20))
        speech.start(.page(start.page), at: start.spot)
        return start
    }

    /// `-seedDemoArticle`: one deterministic article in no folder (and, with `-seedPlayedPages N`,
    /// N pages played without saving).
    static func seedDemoArticle(_ demo: LaunchOptions.DemoArticle, in library: LibraryStore) {
        let context = library.context
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
        // A fresh key each launch, so no audio rendered by an earlier test carries over.
        let page = Page(key: UUID(), title: "Demo Listen Article", byline: "example.com",
                        urlString: "https://example.com/demo", contentState: .saved, addedAt: .now,
                        sortKey: library.nextSortKey(in: nil))
        seedText(page, html: demo.plainTextOnly ? "" : html, plain: plain)
        context.insert(page)
        for i in 0..<demo.playedPages {
            let text = ["Played page \(i + 1), first paragraph.", "Played page \(i + 1), second paragraph."]
            let played = Page(key: UUID(), title: "Played Page \(i + 1)", byline: "example.com",
                              urlString: "https://example.com/played-\(i + 1)", contentState: .saved, addedAt: nil)
            seedText(played, html: text.map { "<p>\($0)</p>" }.joined(), plain: text.joined(separator: "\n\n"))
            played.lastPlayedAt = Date.now.addingTimeInterval(-60 * Double(i + 1))
            context.insert(played)
        }
        library.commit("demo seed")
    }

    /// A seeded page's text, as saving the page would store it: its listen paragraphs built from
    /// `html` and `plain` by the reader's rules (`Page.buildListenDocument`), and a real word count.
    private static func seedText(_ page: Page, html: String, plain: String) {
        let paragraphs = Page.buildListenDocument(plainText: plain, cleanedHTML: html, title: page.title).paragraphs
        page.setText(html: html, plain: plain, excerpt: String(plain.prefix(140)), paragraphs: paragraphs)
    }

    /// `-bakeArticle <id prefix>` (e.g. `xcrun devicectl device process launch …
    /// com.jimmyyao.Reader -- -bakeArticle 0C25B7EE`; without the `--`, devicectl takes the
    /// argument for its own flags): render a saved article's audio top-down without playing it,
    /// then read ListenTiming / TTSCache.
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
        speech.localTTS.startBakeIfNeeded(articleID: page.listenKey, paragraphs: paragraphs)
    }

    /// `-seedBookmarks`: five starred links on `example.com` hosts. They count as this launch's
    /// icon fetch already tried (`LibraryStore.iconTried`), so their icons stay letter tiles and
    /// nothing goes to the network for them.
    static func seedBookmarks(in library: LibraryStore) {
        let seeds = [
            ("https://books.example.com/", "Public Domain Books"),
            ("https://wiki.example.com/Speech_synthesis", "Speech synthesis"),
            ("https://news.example.com/", "News Front Page"),
            ("https://tech.example.com/", "Tech Review"),
            ("https://example.com/", "Example"),
        ]
        for (address, title) in seeds {
            guard let url = URL(string: address), let page = try? library.addFavorite(url: url, title: title, artwork: nil),
                  let key = page.key else { continue }
            library.iconTried.insert(key)
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
