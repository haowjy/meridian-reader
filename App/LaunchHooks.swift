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
    /// settings' owners store (each names its own, `storedKeys`; a new owner joins the union
    /// here, a voice library's through its provider), and the download list. Launch-step done
    /// flags stay. Launch arguments (`-reading.theme sepia`) still apply over what is cleared.
    static func resetStoredSettings(engines: EngineRegistry, defaults: UserDefaults = .standard,
                                    downloads: DownloadListStore = DownloadListStore()) {
        let keys = SpeechController.storedKeys + LocalTTSCoordinator.storedKeys(for: engines)
            + AppAppearance.storedKeys + ReadingAppearance.storedKeys + LibraryTopLevel.storedKeys
            + RecentSearches.storedKeys + ContentBlocker.storedKeys + SurfaceMemoryStore.storedKeys
            + DeveloperSettings.storedKeys
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
        if options.bigFolderArticles > 0 { seedBigFolder(articles: options.bigFolderArticles, in: library) }
    }

    /// `-seedBigFolder N`: "Big Folder" with N short saved pages, for timing rows and menus.
    static func seedBigFolder(articles count: Int, in library: LibraryStore) {
        guard let folder = try? library.makeFolder(name: "Big Folder", in: nil) else { return }
        for i in 1...count {
            let paragraphs = (1...3).map { "Big page \(i), paragraph \($0). A synthetic note for the timing probe." }
            _ = try? library.save(webPage("Big Page \(i)", at: "https://example.com/big-\(i)", paragraphs: paragraphs),
                                  placement: .folder(folder))
        }
        library.commit("big folder seed")
    }

    /// `-resetLibrary`: every page (link pages too) and every folder goes, each page's audio,
    /// queued renders and bake job with it (as a delete does), and the browsing history, in one
    /// save. The folders are empty by the time they go, and nothing in the app clears the
    /// history, so those two are deleted directly.
    static func resetLibrary(_ library: LibraryStore) {
        let context = library.context
        _ = try? library.edit("reset library") {
            for article in (try? context.fetch(FetchDescriptor<Article>())) ?? [] { library.deleteWithoutSaving(article) }
            for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] { context.delete(folder) }
            for visit in (try? context.fetch(FetchDescriptor<RecentVisit>())) ?? [] { context.delete(visit) }
        }
    }

    /// `-seedDemoFolders`: "Demo Finance" with the subfolders "Bonds" (holding "Coupon Basics") and
    /// "Taxes", and three saved pages of its own, one part-way and one finished. Synthetic text,
    /// `example.com` addresses. Made, saved and marked as the app does; the part-way page's play
    /// is then dated an hour back, which no store write does (a play is dated as it starts, and
    /// makes the page its folder's place).
    static func seedDemoFolders(in library: LibraryStore) {
        guard let finance = try? library.makeFolder(name: "Demo Finance", in: nil),
              let bonds = try? library.makeFolder(name: "Bonds", in: finance),
              (try? library.makeFolder(name: "Taxes", in: finance)) != nil else { return }
        func save(_ title: String, slug: String, in folder: Folder, playhead: Int? = nil) -> Article? {
            let paragraphs = (1...6).map { "\(title), paragraph \($0). A synthetic note about saving, yields and the plain arithmetic of interest over a few years." }
            let article = webPage(title, at: "https://investing.example.com/\(slug)-\(UUID().uuidString.prefix(6))",
                                  paragraphs: paragraphs)
            return try? library.save(article, placement: .folder(folder), playhead: playhead)
        }
        _ = save("Coupon Basics", slug: "coupons", in: bonds)
        let yield = save("Seven-Day Yield", slug: "yield", in: finance, playhead: 3)
        if let funds = save("Money Market Funds", slug: "funds", in: finance) { try? library.setFinished([funds], true) }
        _ = save("Index Funds", slug: "index", in: finance)
        yield?.lastPlayedAt = .now.addingTimeInterval(-3600)
        library.commit("demo folders seed")
    }

    /// After the migrations, before crash resume: bake, bookmarks, and where the app starts.
    static func runAfterMigrations(_ options: LaunchOptions, library: LibraryStore, speech: SpeechController,
                                   shell: ShellState) {
        if let prefix = options.bakeArticlePrefix { bakeArticle(prefix: prefix, in: library, speech: speech) }
        if options.seedsBookmarks { seedBookmarks(in: library) }
        if options.seedsHistory { seedHistory(in: library) }
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
            ListenTimingLog.log("debug_import_test_epub", ["ok": true, "chapters": library.articles(in: book).count], console: true)
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
        ListenTimingLog.log("debug_play_test_epub", ["started": true, "title": start.article.title], console: true)
    }

    /// `-seedDemoBook`: the demo book (a skipped title page and three chapters) and one page in no
    /// folder, replacing the ones an earlier launch seeded, with their audio. Fresh keys each
    /// launch, so no audio rendered before carries over. It runs on a phone with real data (the
    /// chapter-boundary device check), so it removes only rows it marked itself: the book by its
    /// `sourceIdentifier` and its chapters by the book's record (`BookSourceState.chapterKeys`),
    /// wherever they were moved (anything moved into the book moves up out of it), and the page
    /// in no folder by `DemoBook.looseArticleMarker`. An address another page already has isn't given
    /// to a seeded page, since the launch's dedupe would merge the two: that chapter goes without
    /// it, and the page in no folder isn't added.
    /// The book is imported and the page saved as the app does them; then each chapter gets its
    /// offline test page's address (an imported chapter has none) and the page its marker,
    /// directly, as no store write gives either.
    /// `place`: the book is part-way, at that chapter's third paragraph (`-seedDemoBookPlace`),
    /// played ten minutes before (a play through the store is dated as it starts), with the
    /// chapters before it that play finished.
    static func seedDemoBook(in library: LibraryStore, place: Int? = nil) {
        for folder in demoBooks(in: library) {
            for article in (folder.bookState?.chapterKeys ?? []).compactMap(library.article(key:)) { library.delete(article) }
            let strays = library.subfolders(of: folder).map(LibraryItem.folder) + library.articles(in: folder).map(LibraryItem.article)
            try? library.move(strays, to: folder.parent)
            try? library.deleteFolder(folder)
        }
        for article in seededLooseArticles(in: library) { library.delete(article) }
        let details = FolderDetails(kind: .book, title: DemoBook.title, byline: DemoBook.author,
                                    sourceIdentifier: DemoBook.sourceIdentifier)
        let chapters = DemoBook.chapters.enumerated().map { index, chapter in
            let locator = EPUBLocator(href: "chapter-\(index).xhtml", anchor: .fileStart)
            return ArticleContent(ref: ArticleRef(key: UUID(), locator: .book(locator), ordinal: index,
                                            skipsInPlayback: chapter.skipsInPlayback),
                               title: chapter.title, bodyHTML: chapter.html, plainText: chapter.plainText,
                               excerpt: String(chapter.plainText.prefix(140)))
        }
        guard let book = try? library.addBook(details, chapters: chapters, in: nil) else { return }
        let articles = library.articles(in: book, sort: .manual)
        for (index, article) in articles.enumerated() {
            let url = DemoBook.url(ofChapter: index)
            guard library.article(url: url) == nil else { continue }
            article.urlString = url.absoluteString
            article.canonicalURL = ArticleIdentity.canonicalURLString(from: url)
        }
        if let place, articles.indices.contains(place) {
            try? library.setFinished(articles[..<place].filter { !$0.skipsInPlayback }, true)
            articles[place].positionParagraph = 2
            articles[place].lastPlayedAt = .now.addingTimeInterval(-600)
            book.currentArticleKey = articles[place].key
        }
        if library.article(url: DemoBook.looseArticleURL) == nil {
            var loose = webPage(DemoBook.looseArticle.title, at: DemoBook.looseArticleURL.absoluteString,
                                paragraphs: DemoBook.looseArticle.paragraphs)
            loose.sourceLabel = DemoBook.author
            (try? library.save(loose))?.locator = DemoBook.looseArticleMarker
        } else {
            library.log("demo seed: \(DemoBook.looseArticleURL.absoluteString) is another page's; no page in no folder added")
        }
        library.commit("demo book seed")
    }

    /// The demo book an earlier seed added, wherever it was moved.
    private static func demoBooks(in library: LibraryStore) -> [Folder] {
        let source: String? = DemoBook.sourceIdentifier
        return (try? library.context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.sourceIdentifier == source }))) ?? []
    }

    /// The page in no folder an earlier seed added, by its marker.
    private static func seededLooseArticles(in library: LibraryStore) -> [Article] {
        let marker: String? = DemoBook.looseArticleMarker
        return (try? library.context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.locator == marker }))) ?? []
    }

    /// A web page as its extraction gives it, under a fresh key, so no audio rendered before
    /// carries over. `html: false`: the page has only its plain text.
    private static func webPage(_ title: String, at address: String, paragraphs: [String], html: Bool = true) -> ReaderArticle {
        let plain = paragraphs.joined(separator: "\n\n")
        let text = ExtractedArticle(title: title, cleanedHTML: html ? paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n") : "",
                                    plainText: plain, excerpt: String(plain.prefix(140)))
        return ReaderArticle(id: UUID(), url: URL(string: address)!, extracted: text)
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
            "started": true, "key": ListenTimingLog.shortKey(start.article.listenKey), "p": start.spot.paragraph,
            "engine": speech.activeEngine?.name ?? "—", "build": LocalTTSCoordinator.buildConfiguration,
        ], console: true)
    }

    /// Plays `book` from where Continue would, unless something already plays, after waiting
    /// (≤ 20 s) for the on-device engine so it doesn't start on Apple. Returns where it started.
    private static func play(_ book: Folder, library: LibraryStore, speech: SpeechController) async -> (article: Article, spot: ListenSpot)? {
        guard speech.activeSessionID == nil, let start = library.continueStart(of: book) else { return nil }
        await speech.localTTS.waitForEngineLoad(timeout: .seconds(20))
        speech.start(.article(start.article), at: start.spot)
        return start
    }

    /// `-seedDemoArticle`: one deterministic article saved in no folder (and, with
    /// `-seedPlayedPages N`, N pages played without saving, each left at its second paragraph:
    /// part-way). Saved and played as the app does; each play is then dated a minute further back
    /// than the one before ("Played Page 1" most recently), which no store write does (a play is
    /// dated as it starts).
    static func seedDemoArticle(_ demo: LaunchOptions.DemoArticle, in library: LibraryStore) {
        let paragraphs = [
            "First paragraph for listen probe. This one is intentionally longer so Simulator UI tests can press next and previous before speech finishes the whole article on its own.",
            "Second paragraph so next and previous skip have somewhere to go. Extra sentences keep the synthesizer busy while the probe checks speed and paragraph controls.",
            "Third paragraph finishes the demo article used by Simulator UI tests. One more cushion of text so stop can be exercised while playback is still active.",
        ]
        _ = try? library.save(webPage("Demo Listen Article", at: "https://example.com/demo", paragraphs: paragraphs,
                                      html: !demo.plainTextOnly))
        for i in 0..<demo.playedArticles {
            let played = library.recordPlayback(webPage("Played Page \(i + 1)", at: "https://example.com/played-\(i + 1)",
                                                        paragraphs: ["Played page \(i + 1), first paragraph.",
                                                                     "Played page \(i + 1), second paragraph."]))
            library.recordPosition(played, paragraph: 1, utf16Offset: 0)
            played.lastPlayedAt = .now.addingTimeInterval(-60 * Double(i + 1))
        }
        library.commit("demo seed")
    }

    /// `-bakeArticle <id prefix>` (e.g. `xcrun devicectl device process launch …
    /// com.jimmyyao.Reader -- -bakeArticle 0C25B7EE`; without the `--`, devicectl takes the
    /// argument for its own flags): render a saved article's audio top-down without playing it,
    /// then read ListenTiming / TTSCache.
    static func bakeArticle(prefix: String, in library: LibraryStore, speech: SpeechController) {
        let articles = (try? library.context.fetch(FetchDescriptor<Article>())) ?? []
        guard let article = articles.first(where: { $0.hasText && $0.listenKey.uuidString.hasPrefix(prefix) }) else {
            ListenTimingLog.log("debug_bake_article", ["prefix": prefix, "found": false])
            return
        }
        let paragraphs = article.listenDocument().paragraphs
        ListenTimingLog.log("debug_bake_article", [
            "prefix": prefix, "found": true, "key": ListenTimingLog.shortKey(article.listenKey), "paragraphs": paragraphs.count,
        ])
        speech.localTTS.startBakeIfNeeded(articleID: article.listenKey, paragraphs: paragraphs)
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
            guard let url = URL(string: address), let article = try? library.addFavorite(url: url, title: title, artwork: nil),
                  let key = article.key else { continue }
            library.iconTried.insert(key)
        }
    }

    /// `-seedHistory`: three visits on `example.com` hosts, newest last, the last one untitled.
    static func seedHistory(in library: LibraryStore) {
        let visits: [(String, String?)] = [
            ("https://wiki.example.com/Speech_synthesis", "Speech synthesis"),
            ("https://example.com/", "Example"),
            ("https://news.example.com/2026/10/19/tides", nil),
        ]
        for (address, title) in visits {
            if let url = URL(string: address) { library.recordVisit(url: url, title: title, faviconData: nil) }
        }
    }

    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): the newest saved article in the Reader
    /// sheet over the browser, without needing the network.
    static func openNewestInReader(in library: LibraryStore, shell: ShellState) {
        var newest = LibraryQueries.savedInLibrary
        newest.fetchLimit = 1
        guard let saved = try? library.context.fetch(newest).first else { return }
        var article = ReaderArticle(article: saved)
        if article.document.isEmpty {
            let document = Article.buildListenDocument(plainText: saved.plainText, cleanedHTML: saved.cleanedHTML,
                                                    title: saved.givenTitle)
            article.document = document
            article.trustedParagraphs = document.paragraphs
        }
        shell.openReader(article)
    }
}
#endif
