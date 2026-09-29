import SwiftUI
import SwiftData

/// Library entry point into the shared `ArticleReaderScreen` (‹ back chevron: a push inside the
/// library sheet). Takes the article id (not the model) and snapshots it once, so Unsave from the
/// reader keeps the screen and playback alive even after the SwiftData row is deleted.
struct OfflineArticleView: View {
    let articleID: UUID
    @Environment(\.speechController) private var speech
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: ReaderArticle?

    var body: some View {
        Group {
            if let snapshot {
                ArticleReaderScreen(
                    article: snapshot,
                    closeStyle: .back,
                    speech: speech,
                    onClose: { dismiss() },
                    onIdentityChange: { self.snapshot?.id = $0 }
                )
            } else {
                Color(.systemBackground)
            }
        }
        // Keep the system bar (stable across push/pop and the edge swipe); the reader puts its
        // own ‹ row in it. Swipe-back with the back button hidden comes from `SwipeBackSupport`.
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        // Bar material / visibility: set by the reader (clear while its chrome is hidden).
        .task(id: articleID) {
            guard snapshot == nil else { return }
            await ReaderArticle.loadSaved(id: articleID, in: modelContext) { loaded in
                // Ignore the late update if Save rekeyed the article meanwhile.
                if snapshot == nil || snapshot?.id == loaded.id { snapshot = loaded }
            }
        }
    }
}

extension ReaderArticle {
    /// Snapshot a saved row for the reader. Calls `update` with the row right away, then again once
    /// listen blocks are built (older saves build them once off the main thread, then store them).
    @MainActor
    static func loadSaved(id: UUID, in context: ModelContext, update: (ReaderArticle) -> Void) async {
        guard let row = ArticleLibrary.savedArticle(id: id, in: context) else { return }
        row.detectedLanguageBackfilling()
        var article = ReaderArticle(saved: row)
        update(article)
        guard article.document.isEmpty else { return }

        let plain = row.plainText
        let html = row.cleanedHTML
        let title = row.title
        let doc = await Task.detached(priority: .userInitiated) {
            SavedArticle.buildListenDocument(plainText: plain, cleanedHTML: html, title: title)
        }.value
        if let row = ArticleLibrary.savedArticle(id: id, in: context) {
            row.storeListenParagraphs(doc.paragraphs)
            article.storedDetectedLanguage = row.detectedLanguageCode
        }
        article.document = doc
        article.trustedParagraphs = doc.paragraphs
        update(article)
    }
}
