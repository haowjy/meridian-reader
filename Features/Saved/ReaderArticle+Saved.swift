import SwiftUI

extension ReaderArticle {
    /// Snapshot a library page for the reader. Calls `update` with the page right away, then
    /// again once listen blocks are built (older pages build them once off the main thread, then
    /// store them).
    @MainActor
    static func loadSaved(id: UUID, in library: LibraryStore, update: (ReaderArticle) -> Void) async {
        guard let article = library.article(key: id) else { return }
        article.detectedLanguageBackfilling()
        var readerArticle = ReaderArticle(article: article)
        update(readerArticle)
        guard readerArticle.document.isEmpty else { return }

        let plain = article.plainText
        let html = article.cleanedHTML
        let title = article.givenTitle
        let doc = await Task.detached(priority: .userInitiated) {
            Article.buildListenDocument(plainText: plain, cleanedHTML: html, title: title)
        }.value
        if let article = library.article(key: id) {
            article.storeListenParagraphs(doc.paragraphs)
            library.commit("listen blocks")
            readerArticle.storedDetectedLanguage = article.detectedLanguageCode
        }
        readerArticle.document = doc
        readerArticle.trustedParagraphs = doc.paragraphs
        update(readerArticle)
    }
}
