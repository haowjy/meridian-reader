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

    /// After the migration copy, before the layout pass: the demo seed.
    static func runSeeds(_ options: LaunchOptions, library: LibraryStore) {
        if let demo = options.demoArticle { seedDemoArticle(demo, in: library) }
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
