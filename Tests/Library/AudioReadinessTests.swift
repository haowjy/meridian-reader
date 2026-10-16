import SwiftData
import XCTest
@testable import MeridianReader

/// "Audio ready": no listen paragraph of the page still needs audio in the voice
/// (`ArticleAudioCache.missingParagraphs`). Derived from the audio cache, so a voice change, the
/// trim of finished chapters, Delete Downloads and a remap all change it without anything stored
/// on the page; a paragraph with nothing to speak never holds it back.
@MainActor
final class AudioReadinessTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private let paragraphs = ["The first paragraph of the page.", "The second paragraph of the page.",
                              "The third paragraph of the page."]

    private func isReady(_ page: Page, voiceID: String) -> Bool {
        guard let key = page.key else { return false }
        return env.cache.missingParagraphs(articleID: key, paragraphs: page.listenDocument().paragraphs,
                                           engineID: env.tts.cacheEngineID, voiceID: voiceID,
                                           plans: env.tts.chunkPlans).isEmpty
    }

    /// A bare "—" paragraph has nothing to speak and never gets audio: the page is ready once
    /// the others are.
    func testAParagraphWithNothingToSpeakDoesntHoldItBack() throws {
        let text = ["The first paragraph of the page.", "—", "The last paragraph of the page."]
        let page = try library.save(env.article("https://example.com/rule", paragraphs: text))
        let key = try XCTUnwrap(page.key)
        XCTAssertEqual(page.listenDocument().paragraphs, text)
        try env.storeAudio(key, paragraph: 0, text: text[0])
        XCTAssertFalse(isReady(page, voiceID: "voiceA"))
        try env.storeAudio(key, paragraph: 2, text: text[2])
        XCTAssertTrue(isReady(page, voiceID: "voiceA"))
    }

    func testReadyWhenEveryParagraphIsStoredForTheCurrentVoice() throws {
        let page = try library.save(env.article("https://example.com/a", paragraphs: paragraphs))
        let key = try XCTUnwrap(page.key)
        XCTAssertEqual(page.paragraphCount, 3)
        XCTAssertFalse(isReady(page, voiceID: "voiceA"), "nothing rendered")
        try env.storeAudio(key, paragraph: 0, text: paragraphs[0])
        try env.storeAudio(key, paragraph: 1, text: paragraphs[1])
        XCTAssertFalse(isReady(page, voiceID: "voiceA"), "partly rendered")
        try env.storeAudio(key, paragraph: 2, text: paragraphs[2])
        XCTAssertTrue(isReady(page, voiceID: "voiceA"))
        XCTAssertFalse(isReady(page, voiceID: "voiceB"), "another voice isn't ready")
    }

    func testAVoiceChangeMakesItNotReadyUntilRerendered() throws {
        let page = try library.save(env.article("https://example.com/a", paragraphs: paragraphs))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: paragraphs, voice: "voiceA")
        XCTAssertTrue(isReady(page, voiceID: "voiceA"))
        // One paragraph re-rendered in the new voice: the index moves to it, the rest go stale.
        try env.storeAudio(key, paragraph: 0, text: paragraphs[0], voice: "voiceB")
        XCTAssertFalse(isReady(page, voiceID: "voiceB"))
        XCTAssertFalse(isReady(page, voiceID: "voiceA"))
        try env.storeAudio(key, paragraph: 1, text: paragraphs[1], voice: "voiceB")
        try env.storeAudio(key, paragraph: 2, text: paragraphs[2], voice: "voiceB")
        XCTAssertTrue(isReady(page, voiceID: "voiceB"))
    }

    func testDeleteDownloadsMakesItNotReady() throws {
        let page = try library.save(env.article("https://example.com/a", paragraphs: paragraphs))
        try env.storeAudio(page.key!, paragraphs: paragraphs)
        library.deleteDownloads(page)
        XCTAssertFalse(isReady(page, voiceID: "voiceA"))
        XCTAssertTrue(page.isSavedToLibrary, "the page stays saved")
    }

    func testARemapFollowsTheNewParagraphs() throws {
        let page = try library.save(env.article("https://example.com/a", paragraphs: paragraphs))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: paragraphs)
        XCTAssertTrue(isReady(page, voiceID: "voiceA"))

        // The page changed: a new paragraph in front. Opening it refreshes the page and
        // reconciles the audio, which moves to the shifted indices.
        let changed = ["A new opening paragraph."] + paragraphs
        let article = library.readerArticle(url: URL(string: "https://example.com/a")!,
                                            extracted: env.article("https://example.com/a", paragraphs: changed).extracted)
        env.tts.prepareListenIdentity(key: article.id, paragraphs: article.document.paragraphs)
        XCTAssertEqual(page.paragraphCount, 4)
        XCTAssertFalse(isReady(page, voiceID: "voiceA"), "the new paragraph has no audio")
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: 3)?.textHash, ArticleIdentity.paragraphHash(paragraphs[2]))
        try env.storeAudio(key, paragraph: 0, text: changed[0])
        XCTAssertTrue(isReady(page, voiceID: "voiceA"))
    }

    /// D7: finished chapters more than 2 behind the book's place lose their audio; the text
    /// stays, and nearer chapters keep theirs.
    func testTrimDeletesTheAudioOfFinishedChaptersMoreThanTwoBehind() throws {
        let book = Folder(name: "Book", kind: .book)
        env.context.insert(book)
        var chapters: [Page] = []
        for n in 0..<6 {
            let page = try library.save(env.article("https://example.com/ch\(n)", paragraphs: paragraphs))
            page.setFolder(book)
            page.sortKey = Double(n)
            if n < 5 { page.finishedAt = env.now }
            try env.storeAudio(page.key!, paragraphs: paragraphs)
            chapters.append(page)
        }
        book.currentPageKey = chapters[5].key
        try env.context.save()

        XCTAssertEqual(library.trimFinishedAudio(folder: book), 3)
        XCTAssertEqual(chapters.map { isReady($0, voiceID: "voiceA") }, [false, false, false, true, true, true])
        XCTAssertTrue(chapters.allSatisfy { $0.hasText && $0.isSavedToLibrary }, "the text stays")
        XCTAssertEqual(library.trimFinishedAudio(folder: book), 0, "nothing more to trim")

        let plain = try library.makeFolder(name: "Plain", in: nil)
        plain.currentPageKey = chapters[5].key
        XCTAssertEqual(library.trimFinishedAudio(folder: plain), 0, "only books and series")
    }
}
