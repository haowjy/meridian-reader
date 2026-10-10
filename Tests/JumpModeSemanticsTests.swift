import XCTest
@testable import MeridianReader

/// With ☝︎ on, each paragraph of the reading page is a button to assistive tech: "Paragraph N",
/// with the hint "Plays from this paragraph". Off, the paragraphs read as text again.
@MainActor
final class JumpModeSemanticsTests: XCTestCase {
    func testJumpModeMakesEachParagraphAButton() async throws {
        let page = ReadingPageHarness()
        defer { page.close() }
        let doc = ParagraphDocument(plainText: "First line.\n\nSecond line.\n\nThird line.")
        try await page.load(doc.paragraphsHTML, blocks: 3)
        let semantics = """
        Array.from(document.querySelectorAll('[data-reader-index]')).map(function(el) {
          return [el.getAttribute('role') || '', el.getAttribute('aria-label') || '',
                  el.getAttribute('aria-description') || ''].join('|'); }).join(',')
        """

        page.coordinator.setJumpMode(true)
        let on = "button|Paragraph 1|Plays from this paragraph,button|Paragraph 2|Plays from this paragraph,"
            + "button|Paragraph 3|Plays from this paragraph"
        try await page.waitUntil("jump semantics on", timeout: 3) { try await page.js(semantics) as? String == on }

        page.coordinator.setJumpMode(false)
        try await page.waitUntil("jump semantics off", timeout: 3) { try await page.js(semantics) as? String == "||,||,||" }
    }
}
