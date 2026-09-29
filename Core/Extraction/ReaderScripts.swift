import Foundation

/// Bundled JS used around extraction (see Resources/Readability).
enum ReaderScripts {
    /// Removes short invisible text (anti-copy injections) from the live-page snapshot.
    static var visibleSnapshot: String? { source("ReaderVisibleSnapshot") }
    /// Wraps loose text into listen blocks after Readability.
    static var normalizeContent: String? { source("ReaderNormalize") }

    /// `isProbablyReaderable(document)` as one expression (evaluated in an isolated content world).
    static let readerableCheck: String? = source("Readability-readerable").map {
        "(function(){\n" + $0 + "\nreturn isProbablyReaderable(document);\n})()"
    }

    static func source(_ name: String) -> String? {
        let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Readability")
            ?? Bundle.main.url(forResource: name, withExtension: "js")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
