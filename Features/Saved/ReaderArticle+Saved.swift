import SwiftUI

extension ReaderArticle {
    /// Snapshot a library page for the reader. Calls `update` with the page right away, then
    /// again once listen blocks are built (older pages build them once off the main thread, then
    /// store them).
    @MainActor
    static func loadSaved(id: UUID, in library: LibraryStore, update: (ReaderArticle) -> Void) async {
        guard let page = library.page(key: id) else { return }
        page.detectedLanguageBackfilling()
        var article = ReaderArticle(page: page)
        update(article)
        guard article.document.isEmpty else { return }

        let plain = page.plainText
        let html = page.cleanedHTML
        let title = page.givenTitle
        let doc = await Task.detached(priority: .userInitiated) {
            Page.buildListenDocument(plainText: plain, cleanedHTML: html, title: title)
        }.value
        if let page = library.page(key: id) {
            page.storeListenParagraphs(doc.paragraphs)
            library.commit("listen blocks")
            article.storedDetectedLanguage = page.detectedLanguageCode
        }
        article.document = doc
        article.trustedParagraphs = doc.paragraphs
        update(article)
    }
}
