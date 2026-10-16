import SwiftUI
import XCTest
@testable import MeridianReader

/// The reading page (the Reader and Now Playing alike): the spoken paragraph on the highlight in
/// full ink and the rest dimmed (everything in full ink when nothing is spoken), the reading
/// theme, typeface, size and spacing changed live, and Now Playing's title card slot, which the
/// Reader's handed-over offset steps over so the same line stays in the same place.
@MainActor
final class PlayerReadingPageTests: XCTestCase {
    private var page: ReadingPageHarness!

    override func setUp() async throws {
        page = ReadingPageHarness()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    func testOnlyTheSpokenParagraphIsInFullInk() async throws {
        page.coordinator.look = Self.dark
        try await page.load(ReadingPageHarness.paragraphs(3), blocks: 3)
        let ink = try await colour(of: 0)
        XCTAssertEqual(ink, Self.css(Self.dark.colors.ink), "nothing spoken: full ink")

        page.coordinator.setActiveParagraph(1)
        try await page.waitUntil("dimmed", timeout: 3) {
            try await self.colour(of: 0) == Self.css(Self.dark.colors.dim)
        }
        let spoken = try await colour(of: 1)
        let after = try await colour(of: 2)
        XCTAssertEqual(spoken, Self.css(Self.dark.colors.ink), "the spoken paragraph")
        XCTAssertEqual(after, Self.css(Self.dark.colors.dim), "the one after it")
        let tint = try await background(of: 1)
        XCTAssertEqual(tint, Self.css(Self.dark.colors.highlight), "the spoken paragraph's highlight")

        page.coordinator.setActiveParagraph(nil)
        try await page.waitUntil("full ink again", timeout: 3) {
            try await self.colour(of: 0) == Self.css(Self.dark.colors.ink)
        }
    }

    /// A theme chosen while the page is up repaints it in place: no reload, the spoken
    /// paragraph keeps its highlight in the new colours, and the underline takes the new accent.
    func testANewThemeRepaintsThePageInPlace() async throws {
        page.coordinator.look = Self.dark
        try await page.load(ReadingPageHarness.paragraphs(3), blocks: 3)
        page.coordinator.setActiveParagraph(1)
        try await page.waitUntil("dimmed", timeout: 3) { try await self.colour(of: 0) == Self.css(Self.dark.colors.dim) }
        _ = try await page.js("window.__marker = 7")

        page.coordinator.setLook(Self.sepia)
        try await page.waitUntil("sepia", timeout: 3) {
            try await self.colour(of: 0) == Self.css(Self.sepia.colors.dim)
        }
        let spokenBackground = try await background(of: 1)
        XCTAssertEqual(spokenBackground, Self.css(Self.sepia.colors.highlight))
        let page = try await self.page.js("getComputedStyle(document.body).backgroundColor") as? String
        XCTAssertEqual(page, Self.css(Self.sepia.colors.paper))
        let underline = try await self.page.js("getComputedStyle(document.documentElement).getPropertyValue('--underline').trim()") as? String
        XCTAssertEqual(underline, Self.sepia.colors.accent, "one underline colour: the theme's accent")
        let marker = try await self.page.js("window.__marker") as? Int
        XCTAssertEqual(marker, 7, "the same page, not a reload")
    }

    /// The typeface, the text size step and the line spacing apply live too.
    func testTypefaceSizeAndSpacingApplyLive() async throws {
        page.coordinator.sizes = ReadingStyle.Sizes(body: 20, title: 28, caption: 13)
        try await page.load(ReadingPageHarness.paragraphs(3), blocks: 3)
        let before = try await style(of: 0, "fontSize")
        XCTAssertEqual(before, "20px")

        var look = ReadingStyle.Look.standard
        look.font = .rounded
        look.textScale = ReadingTextSize.scale(step: ReadingTextSize.defaultStep + 2)
        look.lineSpacing = .relaxed
        page.coordinator.setLook(look)
        try await page.waitUntil("bigger", timeout: 3) { try await self.style(of: 0, "fontSize") == "24px" }
        let family = try await style(of: 0, "fontFamily")
        XCTAssertTrue(family?.contains("ui-rounded") == true, family ?? "")
        let leading = try await style(of: 0, "lineHeight")
        XCTAssertEqual(leading, "42px", "1.75 × 24 px")
    }

    /// Through the playback session, as Now Playing passes it on: the paragraph in full ink
    /// follows the playhead through a skip, a scrub (the paragraph under the thumb while dragged,
    /// then where it lands) and ⏮, everything is in full ink once the page has finished, and
    /// replay picks the first paragraph out again.
    func testTheSpokenParagraphFollowsThePlayheadThroughTheSession() async throws {
        let test = TestSpeech()
        defer { test.tearDown() }
        let speech = test.speech
        let article = TestSpeech.article("https://example.com/dimming")
        page.coordinator.look = Self.dark
        try await page.load(article.displayHTML, blocks: 3)

        func shows(_ spoken: Int?, scrubPreview: Int? = nil, _ what: String) async throws {
            XCTAssertEqual(speech.spokenParagraph(scrubPreview: scrubPreview), spoken, what)
            page.coordinator.setActiveParagraph(speech.spokenParagraph(scrubPreview: scrubPreview))
            let expected = (0..<3).map {
                spoken == nil || $0 == spoken ? Self.css(Self.dark.colors.ink) : Self.css(Self.dark.colors.dim)
            }
            var colours: [String?] = []
            try await page.waitUntil(what, timeout: 3) {
                colours = []
                for i in 0..<3 { colours.append(try await self.colour(of: i)) }
                return colours == expected
            }
            XCTAssertEqual(colours, expected, what)
        }

        speech.listen(to: article)
        try await shows(0, "listening from the start")
        speech.skipToNextParagraph()
        try await shows(1, "⏭")
        try await shows(2, scrubPreview: 2, "scrubbing over the third paragraph")
        speech.seek(toUTF16Offset: speech.document.startUTF16Offset(forParagraph: 2))
        try await shows(2, "the scrub landed")
        speech.skipToPreviousParagraph()
        try await shows(1, "⏮")
        test.apple.emit(.position(paragraph: 2, utf16: speech.document.startUTF16Offset(forParagraph: 2)))
        try await shows(2, "the engine moved on")
        test.apple.emit(.finished)
        XCTAssertEqual(speech.nowPlaying?.isFinished, true)
        try await shows(nil, "finished: all in full ink")
        speech.press(.page(article.id)) {}
        try await shows(0, "replay")
    }

    func testTheHandedOverOffsetStepsOverTheTitleCard() async throws {
        page.coordinator.look = Self.dark
        page.coordinator.setTopView(ReadingTopView(id: 1, view: AnyView(Color.clear.frame(height: 120))))
        try await page.load(ReadingPageHarness.paragraphs(40), blocks: 40, opensAt: .text(offset: 1200))
        try await page.waitUntil("restored", timeout: 3) { !self.page.coordinator.isRestoringScroll }
        // The slot plus its margin below.
        XCTAssertEqual(page.coordinator.textTop, 120 + Spacing.l, accuracy: 1)
        XCTAssertEqual(page.offset, 1200 + page.coordinator.textTop, accuracy: 1)
    }

    /// The Reader hands its scroll position to Now Playing: the same line is at the same place on
    /// screen. Between the two, the web view starts lower (Now Playing's header is taller), the
    /// title and source line give way to the title card, and the insets differ. An HTML and a
    /// plain-text article, at the default text size and at the largest.
    func testTheHandedOverLineStaysAtTheSamePlaceOnScreen() async throws {
        let plain = ParagraphDocument(plainText: (1...40).map {
            "Line \($0) of the plain text. " + String(repeating: "The tide comes in over the flats. ", count: $0 % 4 + 1)
        }.joined(separator: "\n\n")).paragraphsHTML
        let articles = [("HTML", ReadingPageHarness.paragraphs(40)), ("plain text", plain)]
        let sizes: [(String, UIContentSizeCategory, DynamicTypeSize)] = [
            ("default", .large, .large), ("AX5", .accessibilityExtraExtraExtraLarge, .accessibility5),
        ]
        for (kind, html) in articles {
            for (sizeName, category, dynamicType) in sizes {
                let what = "\(kind), \(sizeName)"
                let textSizes = ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory: category))
                let size = CGSize(width: 402, height: 874)

                let reader = ReadingPageHarness(size: size, viewportTop: 70)
                reader.coordinator.sizes = textSizes
                reader.coordinator.setTextInsets(ReaderTextInsets(top: 0, bottom: 140))
                try await reader.load(html, blocks: 40,
                                      heading: ReaderHeading(title: "Notes on the Lighthouse", detail: ["example.com", "9 min"]))
                try await reader.waitUntil("Reader laid out", timeout: 3) { reader.maxOffset > 1500 }
                let lineInReader = try await reader.windowY(ofParagraph: 12)
                reader.scrollView.contentOffset.y += lineInReader - 300
                let before = try await reader.windowY(ofParagraph: 12)
                XCTAssertEqual(before, 300, accuracy: 1, "\(what): paragraph 13 mid-screen in the Reader")
                let handOver = try XCTUnwrap(reader.coordinator.handOver, what)

                let player = ReadingPageHarness(size: size, viewportTop: dynamicType.isAccessibilitySize ? 190 : 120)
                player.coordinator.look = Self.dark
                player.coordinator.sizes = textSizes
                player.coordinator.setTextInsets(ReaderTextInsets(top: 0, bottom: 260))
                player.coordinator.setTopView(ReadingTopView(id: 1, view: AnyView(
                    TitleCard(title: "Notes on the Lighthouse", detail: ["example.com", "9 min left"], artworkLetter: "e",
                              palette: ReadingTheme.dark.palette(accent: .jade))
                        .environment(\.dynamicTypeSize, dynamicType))))
                try await player.load(html, blocks: 40, opensAt: handOver)
                try await player.waitUntil("restored", timeout: 3) { !player.coordinator.isRestoringScroll }
                let after = try await player.windowY(ofParagraph: 12)
                XCTAssertNotEqual(player.coordinator.textTop, reader.coordinator.textTop, accuracy: 1,
                                  "\(what): something different above the text")
                XCTAssertEqual(after, before, accuracy: 1, "\(what): the same line at the same place on screen")
                reader.close()
                player.close()
            }
        }
    }

    private static let dark = ReadingStyle.Look(colors: .init(ReadingTheme.dark.palette(accent: .jade), scheme: .light))
    private static let sepia = ReadingStyle.Look(colors: .init(ReadingTheme.sepia.palette(accent: .jade), scheme: .light))

    private func colour(of index: Int) async throws -> String? {
        try await style(of: index, "color")
    }

    private func background(of index: Int) async throws -> String? {
        try await style(of: index, "backgroundColor")
    }

    private func style(of index: Int, _ property: String) async throws -> String? {
        try await page.js("getComputedStyle(document.querySelector('[data-reader-index=\"\(index)\"]')).\(property)") as? String
    }

    /// "#1C1C1E" as the page reports it: "rgb(28, 28, 30)".
    private static func css(_ hex: String) -> String {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return "rgb(\((value >> 16) & 0xFF), \((value >> 8) & 0xFF), \(value & 0xFF))"
    }
}
