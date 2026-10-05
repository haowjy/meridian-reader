import Foundation
@testable import Reader

/// An extractor that holds every extraction until the test lets it finish (or fail), so a test
/// can act while a page is still extracting.
final class DelayedExtractor: ArticleExtracting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<ExtractedArticle, Error>] = []

    func availability(for context: ExtractionContext) async -> ArticleAvailability { .available }

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiting.append(continuation) }
        }
    }

    /// Waits until `count` extractions are being held.
    func waitForPending(_ count: Int = 1) async throws {
        for _ in 0..<2_000 {
            if lock.withLock({ waiting.count }) >= count { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw ExtractionError.engineFailed(message: "no extraction started")
    }

    /// Finishes the oldest held extraction with `article`.
    func finish(with article: ExtractedArticle) {
        lock.withLock { waiting.removeFirst() }.resume(returning: article)
    }

    /// Fails the oldest held extraction.
    func fail(_ error: Error = ExtractionError.emptyContent) {
        lock.withLock { waiting.removeFirst() }.resume(throwing: error)
    }

    /// A readable article, long enough to listen to.
    static func article(title: String) -> ExtractedArticle {
        let paragraphs = [
            "The first paragraph of \(title) runs for a while, with enough words in it to be worth hearing aloud.",
            "A second paragraph follows it, and it also has a fair number of words for the listener to hear.",
            "The third paragraph closes the article.",
        ]
        return ExtractedArticle(title: title, siteName: nil,
                                cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
    }
}
