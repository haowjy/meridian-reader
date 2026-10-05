import SwiftUI
import XCTest
@testable import Reader

/// Now Playing's reading page: lyrics style (the spoken paragraph in full ink, the rest dimmed,
/// everything in full ink when nothing is spoken) and the title card's slot, which the Reader's
/// handed-over offset steps over so the same line stays in the same place.
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
        page.coordinator.look = .player
        try await page.load(ReadingPageHarness.paragraphs(3), blocks: 3)
        let ink = try await colour(of: 0)
        XCTAssertEqual(ink, Self.css(Palette.playerInk), "nothing spoken: full ink")

        page.coordinator.setActiveParagraph(1)
        try await page.waitUntil("dimmed", timeout: 3) {
            try await self.colour(of: 0) == Self.css(Palette.playerDimInk)
        }
        let spoken = try await colour(of: 1)
        let after = try await colour(of: 2)
        XCTAssertEqual(spoken, Self.css(Palette.playerInk), "the spoken paragraph")
        XCTAssertEqual(after, Self.css(Palette.playerDimInk), "the one after it")
        let tint = try await page.js("getComputedStyle(document.querySelector('[data-reader-index=\"1\"]')).backgroundColor") as? String
        XCTAssertEqual(tint, "rgba(0, 0, 0, 0)", "no tint box on the player")

        page.coordinator.setActiveParagraph(nil)
        try await page.waitUntil("full ink again", timeout: 3) {
            try await self.colour(of: 0) == Self.css(Palette.playerInk)
        }
    }

    func testTheHandedOverOffsetStepsOverTheTitleCard() async throws {
        page.coordinator.look = .player
        page.coordinator.setTopView(ReadingTopView(id: 1, view: AnyView(Color.clear.frame(height: 120))))
        try await page.load(ReadingPageHarness.paragraphs(40), blocks: 40, opensAt: 1200)
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
                                      heading: ReaderHeading(title: "Notes on the Lighthouse", detail: "example.com · 9 min"))
                try await reader.waitUntil("Reader laid out", timeout: 3) { reader.maxOffset > 1500 }
                let lineInReader = try await reader.windowY(ofParagraph: 12)
                reader.scrollView.contentOffset.y += lineInReader - 300
                let before = try await reader.windowY(ofParagraph: 12)
                XCTAssertEqual(before, 300, accuracy: 1, "\(what): paragraph 13 mid-screen in the Reader")
                let handOver = try XCTUnwrap(reader.coordinator.handOverOffset, what)

                let player = ReadingPageHarness(size: size, viewportTop: dynamicType.isAccessibilitySize ? 190 : 120)
                player.coordinator.look = .player
                player.coordinator.sizes = textSizes
                player.coordinator.setTextInsets(ReaderTextInsets(top: 0, bottom: 260))
                player.coordinator.setTopView(ReadingTopView(id: 1, view: AnyView(
                    TitleCard(title: "Notes on the Lighthouse", detail: "example.com · 9 min left", artworkLetter: "e")
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

    private func colour(of index: Int) async throws -> String? {
        try await page.js("getComputedStyle(document.querySelector('[data-reader-index=\"\(index)\"]')).color") as? String
    }

    private static func css(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))"
    }
}
