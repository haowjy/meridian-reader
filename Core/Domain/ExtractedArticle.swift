import Foundation

struct ExtractedArticle: Sendable, Equatable {
    var title: String
    var siteName: String?
    var cleanedHTML: String
    var plainText: String
    var excerpt: String
}
