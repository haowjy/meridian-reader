import SwiftUI
import SwiftData

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
