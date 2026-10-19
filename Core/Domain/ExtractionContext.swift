import Foundation

/// What an extractor reads: the page's origin and the HTML snapshot of the live page.
struct ExtractionContext: Sendable {
    var origin: PageOrigin
    var htmlSnapshot: String?
}
