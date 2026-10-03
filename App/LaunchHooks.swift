import Foundation
import SwiftData

/// What the UI-test and diagnostics launch arguments (`LaunchOptions`) do. A normal launch runs
/// none of this.
@MainActor
enum LaunchHooks {
    /// `-seedDemoArticle`: replace the library with one deterministic article, so a stored resume
    /// position can't stick at the end between tests.
    static func seedDemoArticle(_ demo: LaunchOptions.DemoArticle, in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<SavedArticle>())) ?? [] {
            context.delete(row)
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
        let words = SavedArticle.wordCount(of: plainAll)
        context.insert(SavedArticle(
            urlString: "https://example.com/demo",
            title: demo.title ?? "Demo Listen Article",
            siteDomain: "example.com",
            cleanedHTML: htmlAll,
            plainText: plainAll,
            wordCount: words,
            estimatedMinutes: SavedArticle.estimatedMinutes(words: words),
            excerpt: String(plain.prefix(140)),
            playbackParagraphIndex: demo.progress,
            playbackUTF16Offset: 0
        ))
        try? context.save()
    }

    /// `-bakeArticle <id prefix>` (e.g. `xcrun devicectl device process launch …
    /// com.jimmyyao.Reader -bakeArticle 0C25B7EE`): render a saved article's audio top-down
    /// without playing it, then read ListenTiming / TTSCache.
    static func bakeArticle(prefix: String, in context: ModelContext, speech: SpeechController) {
        let rows = (try? context.fetch(FetchDescriptor<SavedArticle>())) ?? []
        guard let row = rows.first(where: { $0.id.uuidString.hasPrefix(prefix) }) else {
            ListenTimingLog.log("debug_bake_article", ["prefix": prefix, "found": false])
            return
        }
        let paragraphs = row.cachedListenParagraphs
            ?? SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML, title: row.title).paragraphs
        ListenTimingLog.log("debug_bake_article", [
            "prefix": prefix, "found": true, "key": ListenTimingLog.shortKey(row.id), "paragraphs": paragraphs.count,
        ])
        speech.localTTS.startBakeIfNeeded(articleID: row.id, paragraphs: paragraphs, voiceID: speech.cacheVoiceID)
    }

    /// `-resetBookmarks` / `-seedBookmarks`.
    static func setUpBookmarks(_ setup: LaunchOptions.BookmarkSetup, in store: BookmarkStore) {
        store.removeAll()
        guard setup == .seed else { return }
        let seeds = [
            ("https://www.gutenberg.org/", "Project Gutenberg"),
            ("https://en.wikipedia.org/wiki/Speech_synthesis", "Speech synthesis"),
            ("https://news.ycombinator.com/", "Hacker News"),
            ("https://www.theverge.com/", "The Verge"),
            ("https://example.com/", "Example"),
        ]
        for (url, title) in seeds {
            if let url = URL(string: url) { store.add(url: url, title: title, faviconData: nil) }
        }
    }

    /// `-openDemoInBrowseReader` (with `-seedDemoArticle`): the newest saved article in the ✕
    /// reader, without needing the network.
    static func openNewestInReader(in context: ModelContext, shell: ShellState) {
        var newest = FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        newest.fetchLimit = 1
        guard let row = try? context.fetch(newest).first else { return }
        var article = ReaderArticle(saved: row)
        if article.document.isEmpty {
            let document = SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML,
                                                            title: row.title)
            article.document = document
            article.trustedParagraphs = document.paragraphs
        }
        shell.showReader(article)
    }
}
