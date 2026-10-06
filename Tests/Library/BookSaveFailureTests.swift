import SwiftData
import UIKit
import XCTest
@testable import Reader

/// An imported book's *Replace* under the library's save rules: it is one edit
/// (`LibraryStore.edit`), so stopping the chapter it changes never stores half of it, and the
/// listening that stop records outlives a Replace that fails. A dropped chapter's audio work acts
/// on the page holding its key when it runs, as every audio record does.
@MainActor
final class BookSaveFailureTests: XCTestCase {
    private var fixture: TestSpeech!
    private var env: LibraryTestEnvironment!
    private var recorder: ListeningProgressRecorder?
    private let notifications = NotificationCenter()
    private var speech: SpeechController { fixture.speech }
    private var library: LibraryStore { env.library }

    private let bookKey = UUID()
    private let one = UUID(), two = UUID(), three = UUID(), four = UUID()
    private let textOne = ["One begins.", "One goes on.", "One ends."]
    private let textTwo = ["Two begins.", "Two goes on.", "Two ends."]
    private let textThree = ["Three begins.", "Three goes on.", "Three ends."]
    private let editedTwo = ["Two begins.", "Two goes on, differently now.", "Two ends."]

    override func setUp() async throws {
        fixture = TestSpeech()
        env = try LibraryTestEnvironment(fileBacked: true)
        recorder = ListeningProgressRecorder(speech: fixture.speech, library: env.library,
                                             notificationCenter: notifications)
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
        env.cleanUp()
    }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    // MARK: - Helpers

    private var details: FolderDetails {
        FolderDetails(kind: .book, title: "The Book", byline: "Ada Example", cover: nil, sourceURL: nil,
                      sourceIdentifier: bookKey.uuidString, languageCode: "en", sourceState: nil)
    }

    private func chapter(_ key: UUID, _ ordinal: Int, _ title: String, _ paragraphs: [String]) -> PageContent {
        let ref = PageRef(key: key, locator: .book(EPUBLocator(href: "OEBPS/c\(ordinal).xhtml", anchor: .fileStart)),
                          ordinal: ordinal, title: title, skipsInPlayback: false)
        return PageContent(ref: ref, title: title, bodyHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                           plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
    }

    private func addBook() throws -> Folder {
        try library.addBook(details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                chapter(three, 2, "Three", textThree)], in: nil)
    }

    /// Chapter one as it was, chapter two edited, chapter three dropped, chapter four new.
    private var replacement: [PageContent] {
        [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo), chapter(four, 2, "Four", ["Four is new."])]
    }

    /// A row's ▶ on `page`, as `LibraryActions.play` does it.
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.toggle(.page(page), resumeParagraph: page.positionParagraph, resumeUTF16Offset: page.positionUTF16)
        }
    }

    /// Replace stops the chapter it changes as the app does (`AppComposition.makeLibrary`), and
    /// stopping records the spot inside the paragraph.
    private func stopsPlaybackOnReplace(then afterStop: @escaping () -> Void = {}) {
        library.stopPlaybackIfPlaying = { [unowned self] key in
            guard speech.activeSessionID == key else { return }
            speech.stop()
            afterStop()
        }
    }

    private func audioWork(in context: ModelContext) -> [LibraryAudioWork] {
        (try? context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
    }

    /// Every file under a key's audio directory in the library's cache, by relative path.
    private func audioFiles(_ key: UUID) throws -> [String: Data] {
        let dir = env.cache.directory(for: key)
        var out: [String: Data] = [:]
        for name in FileManager.default.subpaths(atPath: dir.path) ?? [] {
            var isDir: ObjCBool = false
            let url = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[name] = try Data(contentsOf: url)
        }
        return out
    }

    private func assertBookAsItWas(_ library: LibraryStore, spot: (paragraph: Int, utf16: Int), audio: [[String: Data]],
                                   _ when: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let book = try XCTUnwrap(library.book(key: bookKey), when, file: file, line: line)
        XCTAssertEqual(library.playOrder(of: book).map(\.key), [one, two, three],
                       "\(when): no chapter dropped or added", file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.cachedListenParagraphs, textTwo, "\(when): no text changed", file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.positionParagraph, spot.paragraph, "\(when): the spot stopping recorded",
                       file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.positionUTF16, spot.utf16, "\(when): inside its paragraph", file: file, line: line)
        XCTAssertEqual(try [two, three].map { try audioFiles($0) }, audio, "\(when): no audio aligned or deleted",
                       file: file, line: line)
        XCTAssertTrue(audioWork(in: library.context).isEmpty, "\(when): no audio work waits", file: file, line: line)
    }

    // MARK: - Replace and the chapter it stops

    /// Replace edits the playing chapter and drops another. Stopping that playback records its
    /// spot, and that save works; Replace's own save then fails. Nothing of the Replace is stored,
    /// in the store or on disk: no position save carries it half made. The stopped chapter keeps
    /// its spot, stored once saves work, and a relaunch agrees.
    func testAReplaceThatFailsReplacesNothingThoughStoppingItsPlayingChapterRecordsASpot() throws {
        _ = try addBook()
        for (key, text) in [(two, textTwo), (three, textThree)] { try env.storeAudio(key, paragraphs: text) }
        let audioBefore = try [two, three].map { try audioFiles($0) }
        play(try XCTUnwrap(library.page(key: two)))
        let p1 = speech.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 5))
        var failing = false
        library.saveContext = { if failing { throw SaveFailed() }; try $0.save() }
        stopsPlaybackOnReplace { failing = true }

        let book = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: replacement)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertNil(speech.nowPlaying, "playback of the edited chapter stopped")
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        try assertBookAsItWas(library, spot: (1, p1 + 5), audio: audioBefore, "after the failed Replace")

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        try assertBookAsItWas(env.library, spot: (1, p1 + 5), audio: audioBefore, "after a relaunch")
    }

    /// Saves fail from before the Replace: the spot stopping records can't be saved either. The
    /// Replace's rollback writes it again on the chapter as it was, and it is stored once saves
    /// work.
    func testAReplaceWhileSavesFailKeepsTheStoppedChapterAtItsSpot() throws {
        _ = try addBook()
        for (key, text) in [(two, textTwo), (three, textThree)] { try env.storeAudio(key, paragraphs: text) }
        let audioBefore = try [two, three].map { try audioFiles($0) }
        play(try XCTUnwrap(library.page(key: two)))
        let p2 = speech.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        stopsPlaybackOnReplace()
        failSaves()

        let book = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: replacement)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertNil(speech.nowPlaying, "playback stopped")
        try assertBookAsItWas(library, spot: (2, p2 + 3), audio: audioBefore, "after the failed Replace")

        allowSaves()
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        recorder = nil
        try env.relaunch()
        try assertBookAsItWas(env.library, spot: (2, p2 + 3), audio: audioBefore, "stored once saves work, after a relaunch")
    }

    // MARK: - A dropped chapter's audio work

    /// A Replace edits chapter three, and aligning its audio fails, so that work waits; a second
    /// drops the chapter, and deleting its audio waits behind the align. A third brings the
    /// chapter back. When the next launch runs the waiting work, the delete finds a chapter saved
    /// in the Library holding the key: it keeps the audio and marks it saved, as that page is,
    /// rather than deleting it or leaving it ephemeral.
    func testAWaitingDeleteOfADroppedChapterSettlesItsAudioByThePageAsItIsNow() throws {
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        env.cache.markEphemeral(cacheKey: three)
        let editedThree = ["Three begins.", "Three goes on, otherwise.", "Three ends."]
        let withThree = [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo), chapter(three, 2, "Three", editedThree)]

        env.cache.faultHook = { _ in throw SaveFailed() }
        try library.replaceBook(book, with: details, chapters: withThree)
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo)])
        XCTAssertNil(library.page(key: three), "the drop is saved")
        try library.replaceBook(book, with: details, chapters: withThree)
        XCTAssertNotNil(library.page(key: three), "the chapter is back")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .delete], "the delete waits behind the align")
        XCTAssertTrue(env.cache.hasDirectory(for: three), "nothing deleted yet")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .ephemeral)

        recorder = nil
        try env.relaunch()
        XCTAssertEqual(env.library.finishAudioWork().finished, 2, "next launch: the align, then the delete")
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "both retired")
        XCTAssertEqual(env.cache.readyIndices(articleID: three, paragraphCount: 3, engineID: env.tts.cacheEngineID, voiceID: "voiceA"),
                       [0, 2], "the chapter that came back keeps its audio, aligned to its text")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .saved, "saved, as the chapter is")
    }
}
