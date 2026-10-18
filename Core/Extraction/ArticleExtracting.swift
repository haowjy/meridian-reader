import Foundation

enum ExtractionError: Error, LocalizedError, Equatable {
    case unavailable(reason: String)
    case emptyContent
    case engineFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .emptyContent: return "Couldn’t find a readable article on this page."
        case .engineFailed(let message): return message
        }
    }
}

protocol ArticleExtracting: Sendable {
    func extract(from context: ExtractionContext) async throws -> ExtractedArticle
}
