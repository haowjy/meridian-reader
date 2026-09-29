import Foundation

struct ExtractionContext: Sendable {
    var url: URL
    var pageTitle: String?
    var htmlSnapshot: String?
}
