import XCTest
@testable import MeridianReader

/// Going to the audio puts the spoken sentence, not its paragraph, in the middle of the visible
/// text: opening Now Playing, Jump to Audio, a new paragraph, and the Reader opening at a saved
/// listening spot. A paragraph taller than the screen is the case that matters: its middle is a
/// screen away from its first and last sentences.
@MainActor
final class SpokenSentenceScrollTests: XCTestCase {
    private var page: ReadingPageHarness!
    private let insets = ReaderTextInsets(top: 60, bottom: 120)

    override func setUp() async throws {
        page = ReadingPageHarness(size: CGSize(width: 390, height: 700))
        page.coordinator.setTextInsets(insets)
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    func testFollowingOpensWithTheSpokenSentenceInTheMiddle() async throws {
        page.coordinator.follows = true
        page.coordinator.setActiveParagraph(2)
        page.coordinator.setSentence(Self.sentence(2, 3))
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await assertCentred(Self.sentence(2, 3), "opening")
        try await assertNotCentred(paragraph: 2, "the sentence, not the paragraph's middle")
    }

    /// The sentence can come after the page (Now Playing's sentences are worked out off the main
    /// thread): the text is at the paragraph, then goes to the sentence.
    func testASentenceThatComesLaterIsGoneTo() async throws {
        page.coordinator.follows = true
        page.coordinator.setActiveParagraph(2)
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await page.waitUntilLaidOut()
        page.coordinator.setSentence(Self.sentence(2, 22))
        try await assertCentred(Self.sentence(2, 22), "the sentence once it is known")
    }

    func testJumpToAudioGoesToTheSpokenSentence() async throws {
        page.coordinator.follows = true
        page.coordinator.setActiveParagraph(2)
        page.coordinator.setSentence(Self.sentence(2, 20))
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await assertCentred(Self.sentence(2, 20), "opening")

        // Scrolled away (a drag turns following off), then Jump to Audio.
        page.coordinator.setFollows(false)
        page.scrollView.contentOffset.y = -insets.top
        page.coordinator.setFollows(true)
        try await assertCentred(Self.sentence(2, 20), "Jump to Audio")
    }

    func testANewParagraphGoesToItsSentence() async throws {
        page.coordinator.follows = true
        page.coordinator.setActiveParagraph(1)
        page.coordinator.setSentence(Self.sentence(1, 0))
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await assertCentred(Self.sentence(1, 0), "opening")

        // As `updateUIView` passes them: the sentence, then the paragraph.
        page.coordinator.setSentence(Self.sentence(3, 0))
        page.coordinator.setActiveParagraph(3)
        try await assertCentred(Self.sentence(3, 0), "the next paragraph's first sentence")
    }

    /// Within a long paragraph the text stays put while the spoken sentence is in view, and
    /// brings it back to the middle once it leaves.
    func testFollowingKeepsALongParagraphsSentenceInView() async throws {
        page.coordinator.follows = true
        page.coordinator.setActiveParagraph(2)
        page.coordinator.setSentence(Self.sentence(2, 0))
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await assertCentred(Self.sentence(2, 0), "opening")

        let before = page.offset
        page.coordinator.setSentence(Self.sentence(2, 1))
        try await page.pause(0.6)
        XCTAssertEqual(page.offset, before, accuracy: 0.5, "the next sentence is in view: the text stays")

        page.coordinator.setSentence(Self.sentence(2, 25))
        try await assertCentred(Self.sentence(2, 25), "a sentence out of view")
    }

    /// The Reader at a saved listening spot: it opens with the saved sentence in the middle and
    /// underlined, following nothing.
    func testTheReaderOpensAtTheSavedSentence() async throws {
        page.coordinator.opensAtSentence = true
        page.coordinator.setSentence(Self.sentence(3, 15))
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await assertCentred(Self.sentence(3, 15), "opening")
        let underlined = try await page.js("""
            (function(){ var h = CSS.highlights.get('reader-sentence');
              var r = h && Array.from(h)[0]; return r ? r.toString() : null; })()
            """) as? String
        XCTAssertEqual(underlined, Self.text(3, 15), "the saved sentence is underlined")
    }

    /// Without a saved spot the Reader opens at its top, as before.
    func testTheReaderWithoutASavedSpotOpensAtTheTop() async throws {
        page.coordinator.opensAtSentence = true
        try await page.load(Self.html, blocks: Self.paragraphs)
        try await page.waitUntilLaidOut()
        try await page.pause(0.5)
        XCTAssertEqual(page.offset, -insets.top, accuracy: 0.5)
    }

    /// A saved spot is a document offset; the sentence holding it is what the Reader shows.
    func testTheSavedSpotsSentence() {
        let document = ParagraphDocument(parts: ["One. Two.", "Three here. Four there. Five."])
        let start = document.startUTF16Offset(forParagraph: 1)
        XCTAssertEqual(ReaderSentence(in: document, paragraph: 1, utf16Offset: start + 14),
                       ReaderSentence(paragraph: 1, start: 12, end: 24))
        XCTAssertEqual(ReaderSentence(in: document, paragraph: 1, utf16Offset: 0),
                       ReaderSentence(paragraph: 1, start: 0, end: 12), "outside the paragraph: its first sentence")
        XCTAssertNil(ReaderSentence(in: document, paragraph: 2, utf16Offset: 0))
    }

    // MARK: - The page

    /// Five paragraphs of 30 sentences each, every one far taller than the window.
    private static let paragraphs = 5
    private static let sentencesPerParagraph = 30

    private static func text(_ paragraph: Int, _ sentence: Int) -> String {
        String(format: "Sentence %02d of paragraph %d goes on about the harbour, the boats and the weather.",
               sentence, paragraph)
    }

    private static var html: String {
        (0..<paragraphs).map { p in
            "<p>" + (0..<sentencesPerParagraph).map { text(p, $0) }.joined(separator: " ") + "</p>"
        }.joined(separator: "\n")
    }

    /// Every sentence is the same length, one space apart (its trailing space is part of it).
    private static func sentence(_ paragraph: Int, _ sentence: Int) -> ReaderSentence {
        let length = text(paragraph, sentence).utf16.count
        let start = sentence * (length + 1)
        return ReaderSentence(paragraph: paragraph, start: start, end: start + length)
    }

    /// The middle of the visible text, and of `sentence`, in document y.
    private func middles(of sentence: ReaderSentence) async throws -> (visible: CGFloat, spoken: CGFloat) {
        let rect = try await page.js("window.__readerSpokenRect(\(sentence.paragraph), \(sentence.start), \(sentence.end))")
            as? [Double] ?? []
        let sv = page.scrollView
        let visible = sv.bounds.height - sv.contentInset.top - sv.contentInset.bottom
        let spoken = rect.count == 3 ? CGFloat(rect[0] + rect[1] / 2) : .nan
        return (sv.contentOffset.y + sv.contentInset.top + visible / 2, spoken)
    }

    private func assertCentred(_ sentence: ReaderSentence, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        try await page.waitUntilLaidOut()
        var last: (visible: CGFloat, spoken: CGFloat) = (.nan, .nan)
        try await page.waitUntil("\(what): sentence in the middle", timeout: 5) {
            last = try await self.middles(of: sentence)
            return abs(last.visible - last.spoken) < 1 && !self.page.coordinator.isRestoringScroll
        }
        XCTAssertEqual(last.spoken, last.visible, accuracy: 1, what, file: file, line: line)
    }

    private func assertNotCentred(paragraph: Int, _ what: String,
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        let rect = try await page.js("window.__readerSpokenRect(\(paragraph), null, null)") as? [Double] ?? []
        let (visible, _) = try await middles(of: Self.sentence(paragraph, 0))
        XCTAssertEqual(rect.count, 3)
        XCTAssertGreaterThan(abs(CGFloat(rect[0] + rect[1] / 2) - visible), 200, what, file: file, line: line)
    }
}
