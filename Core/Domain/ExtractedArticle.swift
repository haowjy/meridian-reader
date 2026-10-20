import Foundation

struct ExtractedArticle: Sendable, Equatable {
    /// nil: the page has none (`ArticleRowTitle`).
    var title: String?
    var siteName: String?
    var cleanedHTML: String
    var plainText: String
    var excerpt: String
}
