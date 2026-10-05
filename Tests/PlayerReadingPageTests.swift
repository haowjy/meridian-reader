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

    private func colour(of index: Int) async throws -> String? {
        try await page.js("getComputedStyle(document.querySelector('[data-reader-index=\"\(index)\"]')).color") as? String
    }

    private static func css(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))"
    }
}
