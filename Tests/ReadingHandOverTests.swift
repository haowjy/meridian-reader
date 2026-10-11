import SwiftUI
import XCTest
@testable import MeridianReader

/// Listen in the Reader hands its scroll position to Now Playing (D2), on the real reading pages:
/// - from the Reader's top, Now Playing opens at its top with the title card in full;
/// - scrolled into the text, the same line stays at the same place on screen, also when what is
///   above the text, where the page sits, or the text size changes while it opens;
/// - when the place can't be reached, the line stays in view as near as the page allows;
/// - once open, a text size change keeps the line being read (paragraph and character) in place.
@MainActor
final class ReadingHandOverTests: XCTestCase {
    private static let screen = CGSize(width: 402, height: 874)
    private static let shortTitle = "Tides"
    private static let longTitle = "Notes on the Lighthouse at the Edge of the Northern Sea, with Its Keepers, "
        + "Logs and Lamps Through Two Centuries of Storms"
    private static let sizes: [(String, UIContentSizeCategory, DynamicTypeSize)] = [
        ("default", .large, .large), ("AX5", .accessibilityExtraExtraExtraLarge, .accessibility5),
    ]
    private var pages: [ReadingPageHarness] = []

    override func tearDown() async throws {
        pages.forEach { $0.close() }
        pages = []
    }

    // MARK: The top of the page

    /// The Reader at its top, or scrolled only part way through its title: Now Playing opens at
    /// its top, the title card in full. Scrolled into the text by a few points: the first line
    /// stays where it was, though the card then sits partly above the window's reading area.
    func testFromTheReadersTopNowPlayingOpensAtItsTopAndFromTheTextAtTheSameLine() async throws {
        for title in [Self.shortTitle, Self.longTitle] {
            for (sizeName, category, dynamicType) in Self.sizes {
                let what = "\(title == Self.shortTitle ? "short" : "long") title, \(sizeName)"
                let reader = try await readerPage(title: title, category: category)
                XCTAssertEqual(reader.coordinator.handOver, .top, "\(what): a fresh Reader is at its top")

                reader.scrollView.contentOffset.y = reader.coordinator.textTop / 2
                XCTAssertEqual(reader.coordinator.handOver, .top, "\(what): part way through the title")
                let player = try await playerPage(title: title, dynamicType: dynamicType, category: category,
                                                  opensAt: reader.coordinator.handOver)
                XCTAssertEqual(player.offset, -player.scrollView.contentInset.top, accuracy: 0.5,
                               "\(what): Now Playing at its top")
                XCTAssertGreaterThan(player.coordinator.textTop, 60, "\(what): a title card above the text")

                reader.scrollView.contentOffset.y = reader.coordinator.textTop + 8
                let firstLine = try await reader.windowY(ofParagraph: 0)
                guard case .text = reader.coordinator.handOver else {
                    return XCTFail("\(what): 8 pt into the text hands over the line")
                }
                let scrolled = try await playerPage(title: title, dynamicType: dynamicType, category: category,
                                                    opensAt: reader.coordinator.handOver)
                let after = try await scrolled.windowY(ofParagraph: 0)
                XCTAssertEqual(after, firstLine, accuracy: 1, "\(what): the first line where it was")
                XCTAssertGreaterThan(scrolled.offset, -scrolled.scrollView.contentInset.top,
                                     "\(what): the card has scrolled up with the text")
            }
        }
    }

    /// The Reader at the end of a page with more room below its text than Now Playing has: the
    /// place can't be reached, so Now Playing opens at its end with the last line still in view.
    func testAPlaceThePageCantReachKeepsTheLineInView() async throws {
        let reader = try await readerPage(title: Self.shortTitle, category: .large, bottomInset: 600)
        reader.scrollView.contentOffset.y = reader.maxOffset
        let last = try await reader.windowY(ofParagraph: 39)
        let player = try await playerPage(title: Self.shortTitle, dynamicType: .large, category: .large,
                                          opensAt: reader.coordinator.handOver)
        XCTAssertEqual(player.offset, player.maxOffset, accuracy: 1, "at its end")
        let after = try await player.windowY(ofParagraph: 39)
        let readingArea = 120...(Self.screen.height - 260)
        XCTAssertTrue(readingArea.contains(after), "the last paragraph in view: \(after), was \(last)")
    }

    // MARK: While it opens

    /// While the hand-over waits, the title card grows and the page moves down under a taller
    /// header: the line still lands where it was in the Reader.
    func testChangesAboveTheTextWhileItOpensKeepTheLine() async throws {
        let reader = try await readerPage(title: Self.shortTitle, category: .large)
        try await scroll(reader, paragraph: 12, toWindowY: 300)
        let player = try await playerPage(title: Self.shortTitle, dynamicType: .large, category: .large,
                                          opensAt: reader.coordinator.handOver, waits: true)
        XCTAssertTrue(player.coordinator.isRestoringScroll, "still opening")
        let cardBefore = player.coordinator.textTop

        player.coordinator.setTopView(card(Self.longTitle, detail: ["example.com", "9 min left", "read twice before"],
                                           dynamicType: .large, id: 2))
        player.moveViewport(top: 160)
        try await finishOpening(player)

        XCTAssertGreaterThan(player.coordinator.textTop, cardBefore + 10, "the card grew")
        let after = try await player.windowY(ofParagraph: 12)
        XCTAssertEqual(after, 300, accuracy: 1, "the same line at the same place")
    }

    /// While the hand-over waits, the text size goes to the largest: the line that was at the top
    /// of Now Playing's reading area (the same character, mid-paragraph) stays there.
    func testATextSizeChangeWhileItOpensKeepsTheLine() async throws {
        let reader = try await readerPage(title: Self.shortTitle, category: .large)
        // Now Playing's reading area starts at 120: put the middle of paragraph 13 there.
        try await scroll(reader, paragraph: 12, toWindowY: 120 - 40)
        let line = try await self.line(in: reader, paragraph: 12, atWindowY: 120)
        XCTAssertGreaterThan(line.offset, 0, "mid-paragraph")

        let player = try await playerPage(title: Self.shortTitle, dynamicType: .large, category: .large,
                                          opensAt: reader.coordinator.handOver, waits: true)
        XCTAssertTrue(player.coordinator.isRestoringScroll, "still opening")
        applyLargestText(to: player, title: Self.shortTitle)
        try await finishOpening(player)

        let after = try await windowY(of: player, paragraph: 12, character: line.offset)
        XCTAssertEqual(after, line.y, accuracy: 1, "character \(line.offset) of paragraph 13, on the same line")
    }

    // MARK: Once open

    /// Reading in the Reader or in Now Playing, mid-paragraph, the text size goes to the largest:
    /// the line at the top of the reading area (the same character) stays where it was. At the top,
    /// the page stays at its top.
    func testATextSizeChangeKeepsTheLineBeingRead() async throws {
        for player in [false, true] {
            let what = player ? "Now Playing" : "the Reader"
            let page = player
                ? try await playerPage(title: Self.shortTitle, dynamicType: .large, category: .large, opensAt: nil)
                : try await readerPage(title: Self.shortTitle, category: .large)
            let readingTop = page.webView.frame.minY + page.scrollView.contentInset.top
            try await scroll(page, paragraph: 12, toWindowY: readingTop - 40)
            let line = try await self.line(in: page, paragraph: 12, atWindowY: readingTop)
            XCTAssertGreaterThan(line.offset, 0, "\(what): mid-paragraph")

            let fontSize = { try await page.js("getComputedStyle(document.querySelector('[data-reader-index=\"12\"]')).fontSize") as? String }
            let sizeBefore = try await fontSize()
            if player { applyLargestText(to: page, title: Self.shortTitle) } else {
                page.coordinator.setSizes(Self.largest)
            }
            try await settle(page)
            let after = try await windowY(of: page, paragraph: 12, character: line.offset)
            XCTAssertEqual(after, line.y, accuracy: 1, "\(what): character \(line.offset) of paragraph 13 in place")
            let sizeAfter = try await fontSize()
            XCTAssertNotEqual(sizeAfter, sizeBefore, "\(what): the text did grow")

            page.scrollView.contentOffset.y = -page.scrollView.contentInset.top
            try await page.pause(0.3) // as a finger would leave it, before the size changes
            page.coordinator.setSizes(ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory: .large)))
            try await settle(page)
            XCTAssertEqual(page.offset, -page.scrollView.contentInset.top, accuracy: 0.5, "\(what): the top stays the top")
        }
    }

    // MARK: Pages

    private static let largest = ReadingStyle.Sizes(traits: UITraitCollection(
        preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))

    /// The Reader: 40 paragraphs under the title and source line, its header 70 pt tall.
    private func readerPage(title: String, category: UIContentSizeCategory,
                            bottomInset: CGFloat = 140) async throws -> ReadingPageHarness {
        let page = ReadingPageHarness(size: Self.screen, viewportTop: 70)
        pages.append(page)
        page.coordinator.sizes = ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory: category))
        page.coordinator.setTextInsets(ReaderTextInsets(top: 0, bottom: bottomInset))
        try await page.load(ReadingPageHarness.paragraphs(40), blocks: 40,
                            heading: ReaderHeading(title: title, detail: ["example.com", "9 min"]))
        try await page.waitUntilLaidOut()
        try await page.waitUntil("Reader laid out", timeout: 3) { page.maxOffset > 1500 && page.coordinator.textTop > 0 }
        return page
    }

    /// Now Playing: the same text under the title card, its header taller (120 pt, 190 at AX5),
    /// opening at `opensAt`. `waits`: it stays opening (quiet for 1.5 s) for the test to change
    /// things underneath; otherwise it has finished opening.
    private func playerPage(title: String, dynamicType: DynamicTypeSize, category: UIContentSizeCategory,
                            opensAt: ReadingHandOver?, waits: Bool = false) async throws -> ReadingPageHarness {
        let page = ReadingPageHarness(size: Self.screen, viewportTop: dynamicType.isAccessibilitySize ? 190 : 120)
        pages.append(page)
        page.coordinator.look = .player
        page.coordinator.sizes = ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory: category))
        page.coordinator.setTextInsets(ReaderTextInsets(top: 0, bottom: 260))
        page.coordinator.setTopView(card(title, dynamicType: dynamicType))
        if waits { page.coordinator.restoreTiming = (quiet: 1.5, limit: 6) }
        try await page.load(ReadingPageHarness.paragraphs(40), blocks: 40, opensAt: opensAt)
        try await page.waitUntilLaidOut()
        if waits {
            try await page.waitUntil("laid out", timeout: 3) { page.maxOffset > 1500 }
        } else {
            try await finishOpening(page)
        }
        return page
    }

    private func card(_ title: String, detail: [String] = ["example.com", "9 min left"], dynamicType: DynamicTypeSize,
                      id: Int = 1) -> ReadingTopView {
        ReadingTopView(id: [AnyHashable(id), AnyHashable(dynamicType)], view: AnyView(
            TitleCard(title: title, detail: detail, artworkLetter: "e").environment(\.dynamicTypeSize, dynamicType)))
    }

    /// What a Dynamic Type change does to Now Playing: the text's sizes and the title card.
    private func applyLargestText(to page: ReadingPageHarness, title: String) {
        page.coordinator.setSizes(Self.largest)
        page.coordinator.setTopView(card(title, dynamicType: .accessibility5))
    }

    private func finishOpening(_ page: ReadingPageHarness) async throws {
        try await page.waitUntil("opened", timeout: 8) {
            !page.coordinator.isRestoringScroll && !page.coordinator.isReflowing
        }
    }

    private func settle(_ page: ReadingPageHarness) async throws {
        try await page.waitUntil("reflowed", timeout: 3) { !page.coordinator.isReflowing }
        try await page.pause(0.2)
    }

    /// Scrolls the page so paragraph `index`'s top is at window y `y`.
    private func scroll(_ page: ReadingPageHarness, paragraph index: Int, toWindowY y: CGFloat) async throws {
        let now = try await page.windowY(ofParagraph: index)
        page.scrollView.contentOffset.y += now - y
        let after = try await page.windowY(ofParagraph: index)
        XCTAssertEqual(after, y, accuracy: 0.5, "paragraph \(index + 1) at \(y)")
    }

    /// The line of paragraph `index` at window y `y`: the first character whose line reaches below
    /// it (each test paragraph is one text node, so its characters are the session's offsets), and
    /// that line's top in the window.
    private func line(in page: ReadingPageHarness, paragraph index: Int,
                      atWindowY y: CGFloat) async throws -> (offset: Int, y: CGFloat) {
        let docY = page.scrollView.convert(CGPoint(x: 0, y: y), from: nil).y
        let found = try await page.js("""
            (function(){ var t = document.querySelector('[data-reader-index="\(index)"]').firstChild;
              var d = document.documentElement.getBoundingClientRect().top, r = document.createRange();
              for (var i = 0; i < t.length; i++) { r.setStart(t, i); r.setEnd(t, i + 1);
                var b = r.getClientRects()[0]; if (b && b.bottom - d > \(Double(docY))) return [i, b.top - d]; }
              return null; })();
            """) as? [Double]
        let pair = try XCTUnwrap(found, "a line of paragraph \(index + 1) at \(y)")
        return (Int(pair[0]), page.scrollView.convert(CGPoint(x: 0, y: pair[1]), to: nil).y)
    }

    /// The window y of the top of the line holding character `offset` of paragraph `index`.
    private func windowY(of page: ReadingPageHarness, paragraph index: Int, character offset: Int) async throws -> CGFloat {
        let top = try await page.js("""
            (function(){ var t = document.querySelector('[data-reader-index="\(index)"]').firstChild;
              var r = document.createRange(); r.setStart(t, \(offset)); r.setEnd(t, \(offset + 1));
              return r.getClientRects()[0].top - document.documentElement.getBoundingClientRect().top; })();
            """) as? Double
        return page.scrollView.convert(CGPoint(x: 0, y: CGFloat(try XCTUnwrap(top))), to: nil).y
    }
}
