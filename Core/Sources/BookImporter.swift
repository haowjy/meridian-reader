import Foundation

/// How an import is going, for the import sheet to show.
enum BookImportProgress: Equatable, Sendable {
    /// Opening the file: the refusals, the package, the contents, the cut.
    case reading
    /// Chapters made ready for listening, of all of them.
    case preparing(title: String, done: Int, total: Int)
    /// Writing the book folder.
    case storing(title: String)
}

/// What to do when the book is already in the Library (decision D13). The same file gives the same
/// keys, so there is no *Keep Both*.
enum ReimportChoice: Equatable, Sendable {
    /// Rebuild its pages in the same folder (`LibraryStore.replaceBook`).
    case replace
    /// Leave it as it is.
    case cancel
}

/// The book as read from the file, before its chapters are prepared: what the import sheet shows
/// while the rest runs. Counts are the cut's; settling may still merge a short chapter.
struct BookImportPreview: Equatable {
    var title: String
    /// The authors, joined.
    var byline: String?
    /// A thumbnail of the cover (`CoverThumbnail`).
    var cover: Data?
    var chapterCount: Int
    /// The titles of the chapters that play, in order (untitled ones left out).
    var chapterTitles: [String]
    /// Chapters skipped in playback (title page, licence …), by title, in order.
    var skippedTitles: [String]
}

enum BookImportOutcome {
    /// A new book folder.
    case added(Folder)
    /// The book's folder, rebuilt.
    case replaced(Folder)
    /// The book was in the Library and the choice was Cancel: nothing changed.
    case alreadyInLibrary(Folder)
}

/// Why a book wasn't imported, as the import sheet says it (one line, with OK).
enum BookImportError: Error, Equatable, LocalizedError {
    case drmProtected
    case fixedLayout
    /// Over `EPUBLimits`' caps: more text, files or bytes than a book needs (a zip bomb lands
    /// here too).
    case tooLarge
    /// Not an EPUB, damaged, or no text. The detail is for the log.
    case unreadable(String)
    /// The folder the book was going into was deleted while it was read.
    case destinationGone
    /// The hidden web view couldn't prepare a chapter's text, or the chapters it made don't meet
    /// the size policy (`BookChapterFinalizer.check`).
    case couldNotPrepare(String)
    case couldNotSave

    init(_ error: EPUBError) {
        switch error {
        case .drmProtected: self = .drmProtected
        case .fixedLayout: self = .fixedLayout
        case .tooLarge: self = .tooLarge
        case .unsafePath(let path): self = .unreadable("unsafe path \(path)")
        case .unreadable(let detail): self = .unreadable(detail)
        }
    }

    var errorDescription: String? {
        switch self {
        case .drmProtected: String(localized: "This book is copy-protected (DRM), so Meridian can't read it.")
        case .fixedLayout: String(localized: "This is a fixed-layout book; its text can't be read in order.")
        case .tooLarge: String(localized: "This book is too large to import.")
        case .unreadable: String(localized: "This file isn't a readable EPUB.")
        case .destinationGone: String(localized: "The folder chosen for this book no longer exists.")
        case .couldNotPrepare: String(localized: "Meridian couldn't prepare this book's text.")
        case .couldNotSave: String(localized: "Meridian couldn't save the book. Try again.")
        }
    }
}

/// Imports an EPUB into the library: read and cut it (off the main thread), make each chapter
/// ready for listening in the hidden web view, settle the chapters on their listen blocks, then
/// store one book folder with one page per chapter in a single save. Front matter is kept as
/// skipped pages. A body chapter still over the bar after settling makes the book be cut again
/// with a lower cap, at most `maxCuts` times.
///
/// Nothing in the library changes until the last step, and only for chapters that pass the size
/// policy (`BookChapterFinalizer.check`): a book with nothing left to read is unreadable, and one
/// still over the bar after its cuts couldn't be prepared. Cancelling the importing task stops it
/// between chapters and before it stores anything; it throws `CancellationError` and keeps
/// nothing.
@MainActor
struct BookImporter {
    let library: LibraryStore
    var limits = EPUBLimits.standard
    var rules = EPUBCutRules.standard
    var bar = BookChapterFinalizer.Bar.standard
    var maxCuts = 3

    /// `destinationID`: the folder the book goes in (nil = the top level; any folder, a book or
    /// series too). It is evaluated when the import starts and again in the save, so
    /// the book is stored, in that one save, wherever it names then: the import sheet's *Add to*
    /// can change while the book is read. A folder deleted meanwhile fails the import
    /// (`destinationGone`). A book already in the Library stays where it is: `choice` says whether
    /// its pages are rebuilt. `read` gets the book's title, cover and chapters once the file is
    /// read, before anything else.
    func importBook(at fileURL: URL, into destinationID: @autoclosure () -> UUID?,
                    ifAlreadyInLibrary choice: ReimportChoice,
                    progress: (BookImportProgress) -> Void = { _ in },
                    read onRead: (BookImportPreview) -> Void = { _ in }) async throws -> BookImportOutcome {
        _ = try folder(destinationID())
        progress(.reading)
        var rules = rules
        var book = try await read(fileURL, rules: rules)
        onRead(Self.preview(of: book, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent))
        if let existing = library.book(key: book.key), choice == .cancel { return .alreadyInLibrary(existing) }

        let normalizer = ListenContentNormalizer()
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        var source = try await prepare(book, fallbackTitle: fallbackTitle, normalizer: normalizer, progress: progress)
        var cuts = 1
        while let over = BookChapterFinalizer.overCap(source.chapters, bar: bar), cuts < maxCuts {
            rules.maxWords = max(1, rules.maxWords * bar.maxWords / over * 9 / 10)
            library.log("import \(source.folderDetails.title): a chapter has \(over) words; cutting again at \(rules.maxWords)")
            progress(.reading)
            book = try await read(fileURL, rules: rules)
            source = try await prepare(book, fallbackTitle: fallbackTitle, normalizer: normalizer, progress: progress)
            cuts += 1
        }

        let details = source.folderDetails
        progress(.storing(title: details.title))
        var chapters: [PageContent] = []
        for ref in try await source.knownPages() { chapters.append(try await source.content(of: ref)) }
        try checkSizes(chapters, title: details.title, cuts: cuts)
        // From here to the save nothing awaits, so nothing can change under it.
        try Task.checkCancellation()
        do {
            if let existing = library.book(key: book.key) {
                guard choice == .replace else { return .alreadyInLibrary(existing) }
                try library.replaceBook(existing, with: details, chapters: chapters)
                return .replaced(existing)
            }
            return .added(try library.addBook(details, chapters: chapters, in: try folder(destinationID())))
        } catch let error as BookImportError {
            throw error
        } catch {
            throw BookImportError.couldNotSave
        }
    }

    static func preview(of book: EPUBBook, fallbackTitle: String) -> BookImportPreview {
        let authors = book.metadata.authors.joined(separator: ", ")
        return BookImportPreview(
            title: book.metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            byline: authors.isEmpty ? nil : authors,
            cover: book.cover.flatMap { CoverThumbnail.make(from: $0.data) },
            chapterCount: book.chapters.count,
            chapterTitles: book.chapters.filter { !$0.skipsInPlayback }.compactMap(\.title),
            skippedTitles: book.chapters.filter(\.skipsInPlayback).compactMap(\.title))
    }

    /// The folder `id` names as the library has it now (nil: the top level): it may have been
    /// deleted while the book was read.
    private func folder(_ id: UUID?) throws -> Folder? {
        guard let id else { return nil }
        guard let folder = library.folder(id: id) else { throw BookImportError.destinationGone }
        return folder
    }

    /// The last check before the library sees the chapters (`BookChapterFinalizer.check`).
    private func checkSizes(_ chapters: [PageContent], title: String, cuts: Int) throws {
        guard let rejection = BookChapterFinalizer.check(chapters.map(BookChapterFinalizer.Measure.init), bar: bar) else { return }
        library.log("import \(title) refused after \(cuts) cut(s): \(rejection)")
        func chapter(_ title: String?) -> String { title.map { "chapter “\($0)”" } ?? "a chapter with no title" }
        switch rejection {
        case .noText: throw BookImportError.unreadable("no text to read after normalizing")
        case .emptyChapter(let title): throw BookImportError.couldNotPrepare("\(chapter(title)) has no text")
        case .overBar(let title, let words):
            throw BookImportError.couldNotPrepare("\(chapter(title)) has \(words) words after \(cuts) cut(s)")
        case .short(let title, let words):
            throw BookImportError.couldNotPrepare("\(chapter(title)) has \(words) words beside a chapter that could take them")
        }
    }

    /// Reads and cuts the file off the main thread; a cancel during it is seen once it is done.
    private func read(_ fileURL: URL, rules: EPUBCutRules) async throws -> EPUBBook {
        let limits = limits
        let book: EPUBBook
        do {
            book = try await Task.detached(priority: .userInitiated) {
                try EPUBBookReader.read(fileURL: fileURL, limits: limits, rules: rules)
            }.value
        } catch let error as EPUBError {
            throw BookImportError(error)
        } catch {
            throw BookImportError.unreadable(error.localizedDescription)
        }
        try Task.checkCancellation()
        return book
    }

    private func prepare(_ book: EPUBBook, fallbackTitle: String, normalizer: ListenContentNormalizer,
                         progress: (BookImportProgress) -> Void) async throws -> EPUBSource {
        let title = book.metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        do {
            return try await EPUBSource.prepare(book, fallbackTitle: fallbackTitle, normalizer: normalizer, bar: bar) {
                progress(.preparing(title: title, done: $0, total: $1))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BookImportError.couldNotPrepare(error.localizedDescription)
        }
    }
}
