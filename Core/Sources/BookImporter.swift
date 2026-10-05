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
    /// Not an EPUB, damaged, over the caps, or no text. The detail is for the log.
    case unreadable(String)
    /// Books and series hold only their own chapters.
    case notADestination
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
        case .tooLarge: self = .unreadable("over the size caps")
        case .unsafePath(let path): self = .unreadable("unsafe path \(path)")
        case .unreadable(let detail): self = .unreadable(detail)
        }
    }

    var errorDescription: String? {
        switch self {
        case .drmProtected: String(localized: "This book is copy-protected (DRM), so Meridian can't read it.")
        case .fixedLayout: String(localized: "This is a fixed-layout book; its text can't be read in order.")
        case .unreadable: String(localized: "This file isn't a readable EPUB.")
        case .notADestination: String(localized: "Books and series can't hold other pages.")
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

    /// `destination`: the folder the book goes in (nil = the top level). A book already in the
    /// Library stays where it is: `choice` says whether its pages are rebuilt.
    func importBook(at fileURL: URL, into destination: Folder?, ifAlreadyInLibrary choice: ReimportChoice,
                    progress: (BookImportProgress) -> Void = { _ in }) async throws -> BookImportOutcome {
        if let destination, destination.kind.isFixed { throw BookImportError.notADestination }
        let destinationID = destination?.id
        progress(.reading)
        var rules = rules
        var book = try await read(fileURL, rules: rules)
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
            return .added(try library.addBook(details, chapters: chapters, in: try folder(destinationID)))
        } catch let error as BookImportError {
            throw error
        } catch LibraryTreeError.fixedDestination {
            throw BookImportError.notADestination
        } catch {
            throw BookImportError.couldNotSave
        }
    }

    /// The destination as the library has it now (nil: the top level): it may have been deleted
    /// while the book was read.
    private func folder(_ id: UUID?) throws -> Folder? {
        guard let id else { return nil }
        guard let folder = library.folder(id: id) else { throw BookImportError.destinationGone }
        return folder
    }

    /// The last check before the library sees the chapters (`BookChapterFinalizer.check`).
    private func checkSizes(_ chapters: [PageContent], title: String, cuts: Int) throws {
        guard let rejection = BookChapterFinalizer.check(chapters.map(BookChapterFinalizer.Measure.init), bar: bar) else { return }
        library.log("import \(title) refused after \(cuts) cut(s): \(rejection)")
        switch rejection {
        case .noText: throw BookImportError.unreadable("no text to read after normalizing")
        case .emptyChapter(let chapter): throw BookImportError.couldNotPrepare("\(chapter) has no text")
        case .overBar(let chapter, let words):
            throw BookImportError.couldNotPrepare("\(chapter) has \(words) words after \(cuts) cut(s)")
        case .short(let chapter, let words):
            throw BookImportError.couldNotPrepare("\(chapter) has \(words) words beside a chapter that could take them")
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
