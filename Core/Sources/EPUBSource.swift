import Foundation

/// An imported book as a page source: the chapters cut from the EPUB (`EPUBBookReader`), each
/// normalized in the hidden web view (`ListenContentNormalizer`), then settled on their listen
/// blocks (`BookChapterFinalizer`). Everything is prepared up front, so the pages and keys it
/// hands out are final before the library keeps any of them.
@MainActor
final class EPUBSource: PageSource {
    let book: EPUBBook
    let folderDetails: FolderDetails
    let chapters: [PreparedChapter]

    private init(book: EPUBBook, details: FolderDetails, chapters: [PreparedChapter]) {
        self.book = book
        self.folderDetails = details
        self.chapters = chapters
    }

    var details: FolderDetails? { folderDetails }

    /// Normalizes every chapter of `book`, one at a time in `normalizer`'s one web view, reporting
    /// each one done, and settles them. `fallbackTitle`: the book's name when the package has none.
    /// A cancelled task stops before its next chapter (`CancellationError`).
    static func prepare(_ book: EPUBBook, fallbackTitle: String, normalizer: ListenContentNormalizer,
                        bar: BookChapterFinalizer.Bar = .standard,
                        progress: (_ done: Int, _ total: Int) -> Void) async throws -> EPUBSource {
        var prepared: [PreparedChapter] = []
        progress(0, book.chapters.count)
        for chapter in book.chapters {
            try Task.checkCancellation()
            let html = try await normalizer.normalizeBookChapter(chapter.xhtml)
            prepared.append(PreparedChapter(chapter, normalizedHTML: html))
            progress(prepared.count, book.chapters.count)
        }
        let title = book.metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        let authors = book.metadata.authors.joined(separator: ", ")
        let details = FolderDetails(
            kind: .book, title: title, byline: authors.isEmpty ? nil : authors,
            cover: book.cover.flatMap { CoverThumbnail.make(from: $0.data) },
            sourceURL: nil, sourceIdentifier: book.key.uuidString,
            sourceState: try? JSONEncoder().encode(BookSourceState(fileFingerprint: book.fileFingerprint)))
        return EPUBSource(book: book, details: details, chapters: BookChapterFinalizer.finalize(prepared, bar: bar))
    }

    func knownPages() async throws -> [PageRef] {
        chapters.indices.map(ref(at:))
    }

    func content(of ref: PageRef) async throws -> PageContent {
        guard let chapter = chapters.first(where: { $0.key == ref.key }) else { throw PageSourceError.unknownPage }
        let text = chapter.document.paragraphs.joined(separator: "\n\n")
        return PageContent(ref: ref, title: chapter.title, bodyHTML: chapter.html, plainText: text,
                           excerpt: String(text.prefix(140)), languageCode: book.metadata.language)
    }

    private func ref(at index: Int) -> PageRef {
        let chapter = chapters[index]
        return PageRef(key: chapter.key, locator: .book(chapter.locator), ordinal: index,
                       skipsInPlayback: chapter.skipsInPlayback)
    }
}

/// What a book folder keeps about its file (`Folder.sourceStateData`).
struct BookSourceState: Codable, Equatable {
    /// SHA-256 of the EPUB, hex.
    var fileFingerprint: String?
    /// The keys of the chapters the file gave when it was last imported, in its order; the
    /// library writes them (`LibraryStore.addBook`, `replaceBook`). They are the pages *Replace*
    /// rebuilds, wherever they have been moved since (decision D19). A book stored without them
    /// gets them at launch from the pages in it (`LibraryStore.recordBookChapters`).
    var chapterKeys: [UUID]?
}

extension EPUBLocator {
    /// "href#fragment", or the href alone (`Page.locator`).
    var pageLocator: String {
        fragment.map { "\(href)#\($0)" } ?? href
    }
}
