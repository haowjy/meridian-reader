import Foundation

/// What an extractor reads: the page's origin, its title, and the HTML snapshot of the live page.
struct ExtractionContext: Sendable {
    var origin: PageOrigin
    var pageTitle: String?
    var htmlSnapshot: String?
}
