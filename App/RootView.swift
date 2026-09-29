import SwiftUI
import SwiftData

/// App root: the browser is the whole app (no tab bar). The library opens as a sheet from it.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.speechController) private var speech
    @Query private var articles: [SavedArticle]

    var body: some View {
        BrowseStartView()
        .overlay(alignment: .top) {
            if let notice = speech.localTTS.engineCrashNotice {
                EngineNoticeBanner(text: notice) { speech.localTTS.dismissCrashNotice() }
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: speech.localTTS.engineCrashNotice)
        .onAppear {
            seedDemoIfNeeded()
            // Layout v3 first (it needs the stored pre-split blocks): split giant paragraphs,
            // keep position + usable audio (once per row).
            ArticleLibrary.migrateParagraphLayout(in: modelContext, localTTS: speech.localTTS)
            // Identity v2: backfill canonical URLs + merge duplicate saves (idempotent).
            ArticleLibrary.migrate(in: modelContext, localTTS: speech.localTTS)
            bakeArticleIfRequested()
        }
    }

    /// Diagnostics: launch with `-bakeArticle <id prefix>` (e.g. `xcrun devicectl device process
    /// launch … com.jimmyyao.Reader -bakeArticle 0C25B7EE`) to render a saved article's audio
    /// top-down without playing it, then read ListenTiming / TTSCache. No-op without the argument.
    private func bakeArticleIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-bakeArticle"), i + 1 < args.count else { return }
        let prefix = args[i + 1].uppercased()
        guard let row = articles.first(where: { $0.id.uuidString.hasPrefix(prefix) }) else {
            ListenTimingLog.log("debug_bake_article", ["prefix": prefix, "found": false])
            return
        }
        var paragraphs = ReaderArticle(saved: row).document.paragraphs
        if paragraphs.isEmpty {
            paragraphs = SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML,
                                                          title: row.title).paragraphs
        }
        ListenTimingLog.log("debug_bake_article", [
            "prefix": prefix, "found": true, "key": ListenTimingLog.shortKey(row.id), "paragraphs": paragraphs.count,
        ])
        speech.localTTS.startBakeIfNeeded(articleID: row.id, paragraphs: paragraphs,
                                          rate: Float(speech.rateMultiplier), voiceID: speech.cacheVoiceID)
    }

    private func seedDemoIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemoArticle") else { return }
        // Deterministic UI-test seed: wipe prior saves so resume position cannot stick at the end.
        for article in articles {
            modelContext.delete(article)
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
        // Optional `-seedDemoParagraphs N` (background-listening probe): a longer article.
        let extraCount = max(0, UserDefaults.standard.integer(forKey: "seedDemoParagraphs") - 3)
        let extras = (0..<extraCount).map { i in
            "Extra paragraph \(i + 4) keeps the demo going while the app is in the background. "
                + "It talks about harbor \(i + 4), where boats come and go, and the weather changes every hour."
        }
        let plainAll = ([plain] + extras).joined(separator: "\n\n")
        let htmlAll = ([html] + extras.map { "<p>\($0)</p>" }).joined(separator: "\n")
        let words = plainAll.split { $0.isWhitespace || $0.isNewline }.count
        let article = SavedArticle(
            urlString: "https://example.com/demo",
            // Optional `-seedDemoTitle "<title>"` (UI tests: long-title layout checks).
            title: UserDefaults.standard.string(forKey: "seedDemoTitle") ?? "Demo Listen Article",
            siteDomain: "example.com",
            cleanedHTML: htmlAll,
            plainText: plainAll,
            wordCount: words,
            estimatedMinutes: max(1, Int((Double(words) / 200.0).rounded(.up))),
            excerpt: String(plain.prefix(140)),
            // Optional `-seedDemoProgress N` (UI tests: "Continue listening" on the start page).
            playbackParagraphIndex: UserDefaults.standard.integer(forKey: "seedDemoProgress"),
            playbackUTF16Offset: 0
        )
        modelContext.insert(article)
        try? modelContext.save()
    }
}

/// One-line, dismissible notice (e.g. "Kokoro stopped unexpectedly; resumed on the stable route.").
struct EngineNoticeBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .lineLimit(text.count <= 64 ? 1 : 3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("engineNoticeDismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("engineNotice")
    }
}

#Preview {
    RootView()
        .modelContainer(for: [SavedArticle.self, RecentVisit.self], inMemory: true)
}
