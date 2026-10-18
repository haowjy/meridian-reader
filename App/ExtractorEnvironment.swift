import SwiftUI

private struct ArticleExtractorKey: EnvironmentKey {
    static let defaultValue: any ArticleExtracting = MissingArticleExtractor()
}

extension EnvironmentValues {
    /// The app's one extractor (`AppComposition.extractor`), injected by `ReaderApp`. A view tree
    /// without one is a wiring bug: extraction asserts in Debug and fails (never fake-succeeds) in
    /// Release.
    var articleExtractor: any ArticleExtracting {
        get { self[ArticleExtractorKey.self] }
        set { self[ArticleExtractorKey.self] = newValue }
    }
}

private struct MissingArticleExtractor: ArticleExtracting {
    private static let reason = "Reader mode isn't available (no extractor configured)."

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        assertionFailure("articleExtractor was not injected into the environment")
        throw ExtractionError.unavailable(reason: Self.reason)
    }
}
