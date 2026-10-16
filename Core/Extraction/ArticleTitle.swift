import Foundation

/// An extracted page's title as the app shows it: without the site's name after a separator
/// ("Speech synthesis - Wikipedia" → "Speech synthesis"), which the source line already gives.
/// Only a trailing part that names the site (its name, or a label of its host) is taken off;
/// any other title is left as it is.
enum ArticleTitle {
    private static let separators = [" - ", " | ", " – ", " — "]

    static func withoutSiteSuffix(_ title: String, siteName: String?, host: String?) -> String {
        let names = siteNames(siteName: siteName, host: host)
        guard !names.isEmpty else { return title }
        var best: Range<String.Index>?
        for separator in separators {
            if let range = title.range(of: separator, options: .backwards),
               best.map({ range.lowerBound > $0.lowerBound }) ?? true {
                best = range
            }
        }
        guard let separator = best else { return title }
        let head = title[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let tail = normalized(String(title[separator.upperBound...]))
        guard !head.isEmpty, names.contains(tail) else { return title }
        return head
    }

    /// The site's name and its host's labels ("en.wikipedia.org" → "wikipedia"), lowercased
    /// without spaces.
    private static func siteNames(siteName: String?, host: String?) -> Set<String> {
        var names: Set<String> = []
        if let siteName, !siteName.isEmpty { names.insert(normalized(siteName)) }
        if let host {
            let labels = host.lowercased().split(separator: ".").map(String.init)
            for label in labels.dropLast() where label.count >= 3 && label != "www" {
                names.insert(label)
            }
        }
        return names
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}
