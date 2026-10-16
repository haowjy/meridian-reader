import Foundation

/// What address-field text means: an address to load, or a web search. One rule, used by Submit
/// and by the search suggestions, so text the layer suggests searches for is searched when
/// submitted.
///
/// Text with a scheme and host is an address as typed. Otherwise text with no space is an address
/// when its host names a real place: its last label all letters and at least two long (`.com`,
/// `.uk`, `.js`), or an IPv4 address. "3.14", "e.g." and "v1.2" are searches.
enum BrowseURLParser {
    static func destination(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let address = address(from: trimmed) { return address }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    /// True when the text becomes a web search (not an address); false for empty text.
    static func isSearch(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && address(from: trimmed) == nil
    }

    private static func address(from trimmed: String) -> URL? {
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil { return url }
        guard !trimmed.contains(" "), let url = URL(string: "https://\(trimmed)"), let host = url.host,
              namesAPlace(host) else { return nil }
        return url
    }

    /// A host with a letter top-level domain, or an IPv4 address. One trailing dot (a fully
    /// qualified name) is allowed.
    private static func namesAPlace(_ host: String) -> Bool {
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        if labels.count == 4, labels.allSatisfy({ $0.count <= 3 && $0.allSatisfy(\.isASCIIDigit) && Int($0)! <= 255 }) {
            return true
        }
        guard let tld = labels.last else { return false }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
