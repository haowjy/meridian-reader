import Foundation

/// An imported PDF as a page source: pages extracted by `PDFBookReader`, each wrapped as simple
/// listen HTML (`ParagraphDocument.paragraphsHTML`, same shape as *Paste Text…*), then settled on
/// their listen blocks (`BookChapterFinalizer`). No hidden web-view pass — PDFKit already gave
/// plain text.
@MainActor
final class PDFSource: ArticleSource {
    let book: PDFBook
    let folderDetails: FolderDetails
    let chapters: [PreparedChapter]

    private init(book: PDFBook, details: FolderDetails, chapters: [PreparedChapter]) {
        self.book = book
        self.folderDetails = details
        self.chapters = chapters
    }

    var details: FolderDetails? { folderDetails }

    /// Builds listen HTML for every chapter of `book` and settles them. `progress` reports each
    /// one done. A cancelled task stops before its next chapter (`CancellationError`).
    static func prepare(_ book: PDFBook, bar: BookChapterFinalizer.Bar = .standard,
                        progress: (_ done: Int, _ total: Int) -> Void) async throws -> PDFSource {
        var prepared: [PreparedChapter] = []
        progress(0, book.chapters.count)
        for chapter in book.chapters {
            try Task.checkCancellation()
            let html = ParagraphDocument(plainText: chapter.plainText).paragraphsHTML
            prepared.append(PreparedChapter(
                key: chapter.key, title: chapter.title, locator: chapter.locator,
                skipsInPlayback: false, html: html))
            progress(prepared.count, book.chapters.count)
        }
        let details = FolderDetails(
            kind: .book, title: book.title, byline: book.author,
            cover: book.coverJPEG, sourceURL: nil, sourceIdentifier: book.key.uuidString,
            sourceState: try? JSONEncoder().encode(BookSourceState(fileFingerprint: book.fileFingerprint)))
        return PDFSource(book: book, details: details, chapters: BookChapterFinalizer.finalize(prepared, bar: bar))
    }

    func knownArticles() async throws -> [ArticleRef] {
        chapters.indices.map(ref(at:))
    }

    func content(of ref: ArticleRef) async throws -> ArticleContent {
        guard let chapter = chapters.first(where: { $0.key == ref.key }) else { throw ArticleSourceError.unknownArticle }
        let text = chapter.document.paragraphs.joined(separator: "\n\n")
        return ArticleContent(ref: ref, title: chapter.title, bodyHTML: chapter.html, plainText: text,
                           excerpt: String(text.prefix(140)), languageCode: nil)
    }

    private func ref(at index: Int) -> ArticleRef {
        let chapter = chapters[index]
        return ArticleRef(key: chapter.key, locator: .book(chapter.locator), ordinal: index,
                       skipsInPlayback: chapter.skipsInPlayback)
    }
}
