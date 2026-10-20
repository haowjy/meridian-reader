import XCTest
@testable import MeridianReader

/// *Play from Here* (C109): a selection's offset maps to its sentence's start; the Downloads list
/// by page (C110) keeps render order.
final class PlayFromSelectionTests: XCTestCase {
    func testSelectionPlaysFromItsSentenceStart() throws {
        let first = "Tides rise twice a day. Where a bay narrows, the water piles up. High water can reach far."
        let doc = ParagraphDocument(parts: ["Opening paragraph here.", first])
        let base = doc.startUTF16Offset(forParagraph: 1)
        let inSecond = (first as NSString).range(of: "narrows").location
        let spot = try XCTUnwrap(ListenSpot.fromSelection(in: doc, paragraph: 1, offset: inSecond))
        XCTAssertEqual(spot.paragraph, 1)
        XCTAssertEqual(spot.utf16Offset - base, (first as NSString).range(of: "Where").location, "the sentence's start")
        let atStart = try XCTUnwrap(ListenSpot.fromSelection(in: doc, paragraph: 1, offset: 3))
        XCTAssertEqual(atStart.utf16Offset, base, "the first sentence starts the paragraph")
        let outside = try XCTUnwrap(ListenSpot.fromSelection(in: doc, paragraph: 1, offset: 10_000))
        XCTAssertEqual(outside.utf16Offset, base, "past the text: the paragraph's start")
        XCTAssertNil(ListenSpot.fromSelection(in: doc, paragraph: 5, offset: 0))
    }

    func testDownloadArticlesListEachArticleInRenderOrder() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var folder = DownloadRecord(target: .folder(UUID()), title: "F", addedAt: .now,
                                    entries: [.init(key: a, state: .done), .init(key: b), .init(key: c)])
        folder.isPaused = false
        let article = DownloadRecord(target: .article(d), title: "P", addedAt: .now, entries: [.init(key: d)])
        let articles = DownloadArticles(records: [folder, article],
                                  active: .init(recordID: folder.id, key: b, fraction: 0.4),
                                  currentVoice: "v", rendersDownloads: true) { _ in "v" }
        XCTAssertEqual(articles.now.map(\.key), [b])
        XCTAssertEqual(articles.now.first?.status, .downloading(fraction: 0.4))
        XCTAssertEqual(articles.waiting.map(\.key), [c, d], "queue order")
        XCTAssertEqual(articles.done.map(\.key), [a])
    }
}
