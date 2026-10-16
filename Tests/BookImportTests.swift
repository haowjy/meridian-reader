import UIKit
import XCTest
@testable import MeridianReader

/// An EPUB through the whole import: read and cut, each chapter normalized in the hidden web view,
/// settled on its listen blocks, then stored as one book folder at the destination, with progress
/// a sheet can show and refusals it can say.
@MainActor
final class BookImportTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    static let looseText = "Loose text that sits straight in the chapter's div, and is read all the same."
    static let footnote = "The footnote's own words, which are never read inside the chapter."

    /// A title page before the body (landmarks), three chapters (the first with loose text, a
    /// footnote and a picture) and a cover picture.
    static func sampleBook() -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.title = "The Lantern Keeper"
        epub.creators = [("Ada Example", nil), ("Ben Sample", nil)]
        epub.addDocument("title.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section epub:type="titlepage"><h1>The Lantern Keeper</h1><p>Ada Example and Ben Sample</p></section>
        """))
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section id="c1"><h2>Chapter 1: The Harbor</h2>
        <div>\(looseText)</div>
        \(SyntheticEPUB.paragraphs(300, seed: 1))
        <p>A sentence with a note<a epub:type="noteref" href="#fn1">1</a>.</p>
        <aside epub:type="footnote" id="fn1"><p>\(footnote)</p></aside>
        <p><img src="images/map.png" alt="A map"/></p></section>
        """))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c2", heading: "Chapter 2: The Lighthouse", words: 400, seed: 2)))
        epub.addDocument("three.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3: The Tide", words: 400, seed: 3)))
        epub.contents = [
            .init("Title Page", "title.xhtml"),
            .init("Chapter 1: The Harbor", "one.xhtml#c1"), .init("Chapter 2: The Lighthouse", "two.xhtml#c2"),
            .init("Chapter 3: The Tide", "three.xhtml#c3"),
        ]
        epub.landmarks = [("bodymatter", "one.xhtml#c1")]
        epub.extraManifest = "<item id=\"cover\" href=\"cover.png\" media-type=\"image/png\" properties=\"cover-image\"/>\n"
        epub.extraFiles = [(epub.path("cover.png"), coverPNG)]
        return epub
    }

    /// A 1200 × 1800 picture.
    static let coverPNG: Data = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800),
                                                        format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        .pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
        }

    private func importBook(_ epub: SyntheticEPUB, into destination: Folder? = nil, choice: ReimportChoice = .cancel,
                            importer: BookImporter? = nil,
                            progress: (BookImportProgress) -> Void = { _ in }) async throws -> BookImportOutcome {
        let destinationID = destination?.id
        return try await (importer ?? BookImporter(library: library))
            .importBook(at: try epub.write(in: self), into: destinationID, ifAlreadyInLibrary: choice, progress: progress)
    }

    private func added(_ outcome: BookImportOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> Folder {
        guard case .added(let folder) = outcome else {
            XCTFail("expected a new book, got \(outcome)", file: file, line: line)
            throw CancellationError()
        }
        return folder
    }

    // MARK: - The book folder

    func testABookBecomesAFolderWithOnePagePerChapterAtTheDestination() async throws {
        let shelf = try library.makeFolder(name: "Fiction", in: nil)
        let epub = Self.sampleBook()
        let cut = try epub.read(in: self)
        let book = try added(try await importBook(epub, into: shelf))

        XCTAssertEqual(book.kind, .book)
        XCTAssertTrue(book.parent === shelf, "placed at the destination")
        XCTAssertEqual(book.name, "The Lantern Keeper")
        XCTAssertEqual(book.byline, "Ada Example, Ben Sample")
        XCTAssertEqual(book.sourceIdentifier, cut.key.uuidString)
        XCTAssertEqual(try JSONDecoder().decode(BookSourceState.self, from: XCTUnwrap(book.sourceStateData)).fileFingerprint,
                       cut.fileFingerprint)
        let cover = try XCTUnwrap(book.coverData.flatMap(UIImage.init(data:)), "a cover thumbnail")
        XCTAssertEqual(max(cover.size.width * cover.scale, cover.size.height * cover.scale), 600)

        let pages = library.pages(in: book)
        XCTAssertEqual(pages.map(\.title), ["Title Page", "Chapter 1: The Harbor", "Chapter 2: The Lighthouse",
                                            "Chapter 3: The Tide"])
        XCTAssertEqual(pages.map(\.key), cut.chapters.map { Optional($0.key) }, "the chapters' book keys")
        XCTAssertEqual(pages.map(\.locator), ["OEBPS/title.xhtml", "OEBPS/one.xhtml#c1", "OEBPS/two.xhtml#c2",
                                              "OEBPS/three.xhtml#c3"])
        XCTAssertEqual(pages.map(\.skipsInPlayback), [true, false, false, false], "front matter is skipped")
        for page in pages {
            XCTAssertTrue(page.isSaved && page.isInLibrary, "\(page.title) saved, with its content")
            XCTAssertNil(page.urlString)
            XCTAssertEqual(page.byline, "Ada Example, Ben Sample")
            XCTAssertEqual(page.listenBlocksVersion, ListenHTMLBlocks.version)
            XCTAssertEqual(page.cachedListenParagraphs, Page.buildListenDocument(plainText: page.plainText,
                                                                                 cleanedHTML: page.cleanedHTML,
                                                                                 title: page.title).paragraphs,
                           "\(page.title): the stored blocks are the reading blocks")
            XCTAssertEqual(page.paragraphCount, page.cachedListenParagraphs?.count)
        }
        XCTAssertEqual(library.topLevelFolders().map(\.name), ["Fiction"], "nothing else made")
    }

    func testPlayStartsAtChapterOneNotTheTitlePage() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        let start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertEqual(start.page.title, "Chapter 1: The Harbor")
        XCTAssertEqual(start.spot.paragraph, 0)
    }

    func testLooseTextIsReadAndFootnotesPicturesAndNoteMarksAreNot() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        let chapter = try XCTUnwrap(library.pages(in: book).first { $0.title == "Chapter 1: The Harbor" })
        let blocks = try XCTUnwrap(chapter.cachedListenParagraphs)
        XCTAssertEqual(Array(blocks.prefix(2)), ["Chapter 1: The Harbor", Self.looseText], "the loose text is read")
        XCTAssertTrue(blocks.contains("A sentence with a note."), "the note mark is gone")
        XCTAssertFalse(blocks.contains { $0.contains("footnote's own words") })
        XCTAssertFalse(chapter.cleanedHTML.contains("<img"))
        XCTAssertFalse(chapter.cleanedHTML.contains("<a "))
        XCTAssertEqual(chapter.wordCount, WordCount.count(blocks.joined(separator: " ")))
    }

    func testProgressCountsEveryChapter() async throws {
        var steps: [BookImportProgress] = []
        let total = try Self.sampleBook().read(in: self).chapters.count
        _ = try await importBook(Self.sampleBook()) { steps.append($0) }
        let title = "The Lantern Keeper"
        XCTAssertEqual(total, 4)
        XCTAssertEqual(steps, [.reading] + (0...total).map { .preparing(title: title, done: $0, total: total) }
                       + [.storing(title: title)])
    }

    /// A book is a folder like any other (decision D19): another book can be imported into it.
    func testABookIsADestinationLikeAnyFolder() async throws {
        let first = try added(try await importBook(Self.sampleBook()))
        var other = Self.sampleBook()
        other.identifier = "urn:uuid:0f0e0d0c-2222-4333-8444-955566667777"
        let second = try added(try await importBook(other, into: first))
        XCTAssertIdentical(second.parent, first)
    }

    // MARK: - Refusals

    func testRefusalsSayWhyAndKeepNothing() async throws {
        var drm = Self.sampleBook()
        drm.extraFiles.append(("META-INF/encryption.xml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
        <enc:CipherData><enc:CipherReference URI="OEBPS/two.xhtml"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """.utf8)))
        await assertImportError(.drmProtected) { _ = try await self.importBook(drm) }

        var fixed = Self.sampleBook()
        fixed.extraMetadata = "<meta property=\"rendition:layout\">pre-paginated</meta>"
        await assertImportError(.fixedLayout) { _ = try await self.importBook(fixed) }

        let notAZip = try SyntheticEPUB.write(Data("not a zip at all".utf8), in: self)
        do {
            _ = try await BookImporter(library: library).importBook(at: notAZip, into: nil, ifAlreadyInLibrary: .cancel)
            XCTFail("expected a refusal")
        } catch let error as BookImportError {
            guard case .unreadable = error else { return XCTFail("\(error)") }
            XCTAssertEqual(error.localizedDescription, "This file isn't a readable EPUB.")
        }
        XCTAssertEqual(BookImportError.drmProtected.localizedDescription,
                       "This book is copy-protected (DRM), so Meridian can't read it.")
        XCTAssertEqual(BookImportError.fixedLayout.localizedDescription,
                       "This is a fixed-layout book; its text can't be read in order.")
        XCTAssertTrue(env.folders().isEmpty && env.pages().isEmpty, "nothing kept")
    }

    private func assertImportError(_ expected: BookImportError, file: StaticString = #filePath, line: UInt = #line,
                                   _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BookImportError, expected, file: file, line: line)
        }
    }

    // MARK: - Again (D13)

    func testCancelLeavesABookAlreadyInTheLibrary() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        let keys = library.pages(in: book).map(\.key)
        let again = try await importBook(Self.sampleBook(), choice: .cancel)
        guard case .alreadyInLibrary(let existing) = again else { return XCTFail("\(again)") }
        XCTAssertTrue(existing === book)
        XCTAssertEqual(library.pages(in: book).map(\.key), keys)
        XCTAssertEqual(env.folders().count, 1)
    }

    func testReplaceRebuildsTheSameFolder() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        try library.rename(book, to: "Renamed by me")
        let chapterTwo = try XCTUnwrap(library.pages(in: book).first { $0.title == "Chapter 2: The Lighthouse" })
        library.recordPosition(chapterTwo, paragraph: 2, utf16Offset: 10)
        var edited = Self.sampleBook()
        edited.documents[3].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3: The Tide",
                                                                                   words: 420, seed: 9))
        let again = try await importBook(edited, choice: .replace)
        guard case .replaced(let replaced) = again else { return XCTFail("\(again)") }
        XCTAssertTrue(replaced === book)
        XCTAssertEqual(book.name, "Renamed by me", "its name stays")
        XCTAssertEqual(env.folders().count, 1)
        let pages = library.pages(in: book)
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages.first { $0.title == "Chapter 2: The Lighthouse" }?.positionParagraph, 2, "unchanged chapter keeps its place")
        XCTAssertEqual(pages.last?.wordCount, 420, "the edited chapter's text")
    }

    // MARK: - Settling on listen blocks

    func testChaptersAreSettledOnTheirListenBlocksBeforeAnyKeyIsKept() async throws {
        var epub = Self.sampleBook()
        // In the cut, both pass the cutter's 150 words; read, one has 60 words and the other none.
        epub.documents.insert(.init(name: "epigraph.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section id="ep"><p>\(SyntheticEPUB.words(60, seed: 4))</p>
        <aside epub:type="footnote" id="fn9"><p>\(SyntheticEPUB.words(120, seed: 5))</p></aside></section>
        """)), at: 2)
        epub.documents.insert(.init(name: "notes.xhtml", body: SyntheticEPUB.xhtml(body: """
        <section id="nt"><aside epub:type="footnote" id="fn8"><p>\(SyntheticEPUB.words(200, seed: 6))</p></aside></section>
        """)), at: 4)
        epub.contents.insert(.init("Epigraph", "epigraph.xhtml#ep"), at: 2)
        epub.contents.insert(.init("Notes", "notes.xhtml#nt"), at: 4)
        let cut = try epub.read(in: self)
        let epigraph = try XCTUnwrap(cut.chapters.first { $0.title == "Epigraph" })
        let notes = try XCTUnwrap(cut.chapters.first { $0.title == "Notes" })
        XCTAssertFalse(epigraph.skipsInPlayback || notes.skipsInPlayback)
        XCTAssertGreaterThanOrEqual(epigraph.provisionalWordCount, 150)
        XCTAssertGreaterThanOrEqual(notes.provisionalWordCount, 150)

        let book = try added(try await importBook(epub))
        let pages = library.pages(in: book)
        XCTAssertFalse(pages.contains { $0.key == epigraph.key || $0.key == notes.key }, "their keys are never kept")
        XCTAssertEqual(pages.map(\.title), ["Title Page", "Chapter 1: The Harbor", "Chapter 2: The Lighthouse",
                                            "Chapter 3: The Tide"])
        let two = try XCTUnwrap(pages.first { $0.title == "Chapter 2: The Lighthouse" })
        XCTAssertEqual(two.cachedListenParagraphs?.first, SyntheticEPUB.words(60, seed: 4), "the epigraph opens the next chapter")
        for page in pages where !page.skipsInPlayback {
            XCTAssertTrue((100...30_000).contains(page.wordCount), "\(page.title): \(page.wordCount) words")
        }
    }

    func testABodyChapterOverTheBarIsCutAgain() async throws {
        var epub = SyntheticEPUB()
        let parts = (1...3).map { "<h2>Part \($0)</h2>\n" + SyntheticEPUB.paragraphs(900, seed: $0) }
        epub.addDocument("long.xhtml", body: SyntheticEPUB.xhtml(body: "<section id=\"l\">" + parts.joined(separator: "\n") + "</section>"))
        epub.contents = [.init("The Long Chapter", "long.xhtml#l")]
        var importer = BookImporter(library: library)
        importer.rules.maxWords = 1_000
        importer.bar.maxWords = 800
        let firstCut = try epub.read(in: self, rules: importer.rules)
        XCTAssertTrue(firstCut.bodyChapters.contains { $0.provisionalWordCount > 800 }, "the first cut is over the bar")

        var steps: [BookImportProgress] = []
        let book = try added(try await importBook(epub, importer: importer) { steps.append($0) })
        let words = library.pages(in: book).map(\.wordCount)
        XCTAssertGreaterThan(words.count, firstCut.chapters.count)
        XCTAssertTrue(words.allSatisfy { (100...800).contains($0) }, "\(words)")
        XCTAssertEqual(words.reduce(0, +), 2_700 + 3 * 2, "every word kept")
        XCTAssertEqual(steps.filter { $0 == .reading }.count, 2, "read and cut twice")
    }

    // MARK: - The last check before the library

    /// A book whose every chapter is footnotes: it has text to the parser, and none to read.
    /// It has `sampleBook`'s title and identifier, so the same book key.
    static func footnotesOnlyBook() -> SyntheticEPUB {
        let book = sampleBook()
        var epub = SyntheticEPUB()
        epub.title = book.title
        epub.identifier = book.identifier
        for (i, name) in ["notes1.xhtml", "notes2.xhtml"].enumerated() {
            epub.addDocument(name, body: SyntheticEPUB.xhtml(body: """
            <section id="n\(i)"><aside epub:type="footnote" id="fn\(i)"><p>\(SyntheticEPUB.words(300, seed: 20 + i))</p></aside></section>
            """))
        }
        epub.contents = [.init("Notes One", "notes1.xhtml#n0"), .init("Notes Two", "notes2.xhtml#n1")]
        return epub
    }

    private func assertUnreadable(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected the book to be unreadable", file: file, line: line)
        } catch let error as BookImportError {
            guard case .unreadable = error else { return XCTFail("\(error)", file: file, line: line) }
            XCTAssertEqual(error.localizedDescription, "This file isn't a readable EPUB.", file: file, line: line)
        } catch {
            XCTFail("\(error)", file: file, line: line)
        }
    }

    func testABookWithNothingLeftToReadIsUnreadableAndKeepsNothing() async throws {
        let epub = Self.footnotesOnlyBook()
        XCTAssertEqual(try epub.read(in: self).chapters.count, 2, "the parser finds text in it")
        await assertUnreadable { _ = try await self.importBook(epub) }
        XCTAssertTrue(env.folders().isEmpty && env.pages().isEmpty, "no empty book folder")
    }

    func testReplacingABookWithOneWithNothingToReadLeavesItAsItWas() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        let pages = library.pages(in: book)
        let chapterTwo = try XCTUnwrap(pages.first { $0.title == "Chapter 2: The Lighthouse" })
        library.recordPlayback(ReaderArticle(page: chapterTwo))
        library.recordPosition(chapterTwo, paragraph: 2, utf16Offset: 10)
        let empty = Self.footnotesOnlyBook()
        XCTAssertEqual(try empty.read(in: self).key, try Self.sampleBook().read(in: self).key, "the same book key")

        await assertUnreadable { _ = try await self.importBook(empty, choice: .replace) }
        XCTAssertEqual(library.pages(in: book).map(\.key), pages.map(\.key), "every chapter is still there")
        XCTAssertEqual(book.currentPageKey, chapterTwo.key)
        XCTAssertEqual(chapterTwo.positionParagraph, 2)
        XCTAssertEqual(env.folders().count, 1)
    }

    func testABodyChapterStillOverTheBarWhenTheCutsRunOutKeepsNothing() async throws {
        var epub = SyntheticEPUB()
        let parts = (1...3).map { "<h2>Part \($0)</h2>\n" + SyntheticEPUB.paragraphs(900, seed: $0) }
        epub.addDocument("long.xhtml", body: SyntheticEPUB.xhtml(body: "<section id=\"l\">" + parts.joined(separator: "\n") + "</section>"))
        epub.contents = [.init("The Long Chapter", "long.xhtml#l")]
        var importer = BookImporter(library: library)
        importer.rules.maxWords = 1_000
        importer.bar.maxWords = 800
        importer.maxCuts = 1
        XCTAssertTrue(try epub.read(in: self, rules: importer.rules).bodyChapters.contains { $0.provisionalWordCount > 800 })

        do {
            _ = try await importBook(epub, importer: importer)
            XCTFail("expected a refusal")
        } catch let error as BookImportError {
            guard case .couldNotPrepare = error else { return XCTFail("\(error)") }
            XCTAssertEqual(error.localizedDescription, "Meridian couldn't prepare this book's text.")
        }
        XCTAssertTrue(env.folders().isEmpty && env.pages().isEmpty, "nothing kept")
    }

    // MARK: - Cancelling, and a destination that goes

    /// Runs the import in a task of its own that cancels itself at `step`.
    private func importCancelled(at step: @escaping (BookImportProgress) -> Bool, _ epub: SyntheticEPUB,
                                 choice: ReimportChoice = .cancel) async throws -> Result<BookImportOutcome, Error> {
        let file = try epub.write(in: self)
        let library = library
        let task = Task { @MainActor in
            try await BookImporter(library: library).importBook(at: file, into: nil, ifAlreadyInLibrary: choice) { progress in
                if step(progress) { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        return await task.result
    }

    func testACancelledImportKeepsNothing() async throws {
        let steps: [(String, (BookImportProgress) -> Bool)] = [
            ("between chapters", { if case .preparing(_, 1, _) = $0 { true } else { false } }),
            ("before storing", { $0 == .storing(title: "The Lantern Keeper") }),
        ]
        for (name, step) in steps {
            let result = try await importCancelled(at: step, Self.sampleBook())
            guard case .failure(let error) = result else { return XCTFail("\(name): \(result)") }
            XCTAssertTrue(error is CancellationError, "\(name): \(error)")
            XCTAssertTrue(env.folders().isEmpty && env.pages().isEmpty, "\(name): nothing kept")
        }
    }

    func testACancelledReplaceLeavesTheBookAsItWas() async throws {
        let book = try added(try await importBook(Self.sampleBook()))
        let pages = library.pages(in: book).map { ($0.key, $0.wordCount) }
        var edited = Self.sampleBook()
        edited.documents[3].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3: The Tide",
                                                                                   words: 420, seed: 9))
        let result = try await importCancelled(at: { $0 == .storing(title: "The Lantern Keeper") }, edited, choice: .replace)
        guard case .failure(let error) = result, error is CancellationError else { return XCTFail("\(result)") }
        XCTAssertEqual(library.pages(in: book).map(\.key), pages.map(\.0))
        XCTAssertEqual(library.pages(in: book).map(\.wordCount), pages.map(\.1), "the text is the first import's")
    }

    func testADestinationDeletedWhileTheBookIsReadKeepsNothing() async throws {
        let shelf = try library.makeFolder(name: "Fiction", in: nil)
        do {
            _ = try await importBook(Self.sampleBook(), into: shelf) { step in
                if case .preparing(_, 1, _) = step { try? self.library.deleteFolder(shelf) }
            }
            XCTFail("expected a refusal")
        } catch let error as BookImportError {
            XCTAssertEqual(error, .destinationGone)
            XCTAssertEqual(error.localizedDescription, "The folder chosen for this book no longer exists.")
        }
        XCTAssertTrue(env.folders().isEmpty, "no book folder, anywhere")
        XCTAssertTrue(env.pages().isEmpty)
    }
}
