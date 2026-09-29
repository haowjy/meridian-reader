import SwiftUI

private struct ArticleExtractorKey: EnvironmentKey {
    static let defaultValue: any ArticleExtracting = FakeArticleExtractor(mode: .success)
}

extension EnvironmentValues {
    var articleExtractor: any ArticleExtracting {
        get { self[ArticleExtractorKey.self] }
        set { self[ArticleExtractorKey.self] = newValue }
    }
}
