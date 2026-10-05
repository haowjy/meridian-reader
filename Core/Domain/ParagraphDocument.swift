import Foundation

/// Canonical paragraph model for listen + reading surfaces.
/// Views must not re-split; they consume this document.
struct ParagraphDocument: Equatable, Sendable {
    let paragraphs: [String]
    let utf16Ranges: [NSRange]
    let joinedText: String

    var count: Int { paragraphs.count }
    var isEmpty: Bool { paragraphs.isEmpty }
    /// How far through the text `offset` (UTF-16, into `joinedText`) is, 0…1.
    func progress(atUTF16Offset offset: Int) -> Double {
        // The last paragraph's end is the text's length, without measuring the string.
        guard let total = utf16Ranges.last.map(NSMaxRange), total > 0 else { return 0 }
        return min(1, max(0, Double(offset) / Double(total)))
    }

    /// Length of the whole text in UTF-16 units.
    var utf16Length: Int { utf16Ranges.last.map(NSMaxRange) ?? 0 }

    static let empty = ParagraphDocument(paragraphs: [], utf16Ranges: [], joinedText: "")

    /// Prefer HTML block order (headings + paragraphs) so highlight/tap match speech.
    /// `splitLong` = false only reproduces the pre-v3 paragraph list (migration).
    static func forListening(
        plainText: String,
        cleanedHTML: String?,
        matchingTitle: String? = nil,
        splitLong: Bool = true
    ) -> ParagraphDocument {
        if let cleanedHTML {
            let trimmed = cleanedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let stripped = stripLeadingTitleHeading(trimmed, matchingTitle: matchingTitle)
                let html = splitLong ? ListenHTMLBlocks.splitLongBlocks(stripped) : stripped
                let fromHTML = ParagraphDocument(html: html)
                if !fromHTML.isEmpty { return fromHTML }
            }
        }
        return ParagraphDocument(plainText: plainText, splitLong: splitLong)
    }

    /// The HTML the reader displays: leading duplicate title removed, giant paragraphs split at
    /// sentence ends. `forListening` derives the paragraph list from exactly this HTML, so view
    /// indices (highlight, Jump taps, render marks) always match speech and the audio cache.
    static func readingHTML(_ html: String, matchingTitle: String?) -> String {
        ListenHTMLBlocks.splitLongBlocks(stripLeadingTitleHeading(html, matchingTitle: matchingTitle))
    }

    /// The paragraphs as reading HTML, one escaped `<p>` each, for text with no HTML of its own (a
    /// plain-text article). The reading page numbers its leaf blocks in order, so block i is
    /// paragraph i and the tint, underline and follow mode line up with the session.
    /// The text isn't normalized (positions and the audio cache are counted in it): the page maps
    /// sentence offsets over every space, tab and newline of the paragraph.
    var paragraphsHTML: String {
        paragraphs.map { paragraph in
            let escaped = paragraph.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            return "<p>\(escaped)</p>"
        }.joined(separator: "\n")
    }

    init(plainText: String, splitLong: Bool = true) {
        let parts = Self.split(plainText)
        self.init(parts: splitLong ? parts.flatMap(ParagraphSplitter.pieces) : parts)
    }

    init(html: String) {
        self.init(parts: Self.blocks(fromHTML: html))
    }

    init(parts: [String]) {
        let parts = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            self.paragraphs = []
            self.utf16Ranges = []
            self.joinedText = ""
            return
        }
        self.paragraphs = parts
        self.joinedText = parts.joined(separator: "\n\n")
        var ranges: [NSRange] = []
        var location = 0
        for (i, paragraph) in parts.enumerated() {
            let length = paragraph.utf16.count
            ranges.append(NSRange(location: location, length: length))
            location += length
            if i < parts.count - 1 { location += 2 }
        }
        self.utf16Ranges = ranges
    }

    init(paragraphs: [String], utf16Ranges: [NSRange], joinedText: String) {
        self.paragraphs = paragraphs
        self.utf16Ranges = utf16Ranges
        self.joinedText = joinedText
    }

    func index(containingUTF16Offset offset: Int) -> Int {
        guard !utf16Ranges.isEmpty else { return 0 }
        for (i, range) in utf16Ranges.enumerated() {
            let start = range.location
            let end = range.location + range.length
            if offset >= start && offset < end { return i }
            if offset == end, i + 1 < utf16Ranges.count {
                return i + 1
            }
        }
        if offset <= utf16Ranges[0].location { return 0 }
        return paragraphs.count - 1
    }

    func startUTF16Offset(forParagraph index: Int) -> Int {
        guard !utf16Ranges.isEmpty else { return 0 }
        let clamped = max(0, min(index, utf16Ranges.count - 1))
        return utf16Ranges[clamped].location
    }

    static func split(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let byBlank = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if byBlank.count > 1 { return byBlank }

        let byLine = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !byLine.isEmpty { return byLine }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    /// Drop leading `<h1>` when it duplicates the nav/article title (same rule as HTMLReadingView).
    static func stripLeadingTitleHeading(_ html: String, matchingTitle title: String?) -> String {
        guard let title, !title.isEmpty else { return html }
        let pattern = #"(?is)^\s*<h1[^>]*>\s*(.*?)\s*</h1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else { return html }
        let inner = String(html[titleRange])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.caseInsensitiveCompare(title) == .orderedSame else { return html }
        return regex.stringByReplacingMatches(in: html, range: match.range, withTemplate: "")
    }

    /// Leaf listen blocks from shared `ListenHTMLBlocks` (same tags as HTMLReadingView).
    static func blocks(fromHTML html: String) -> [String] {
        ListenHTMLBlocks.leafTexts(fromHTML: html)
    }

    /// Backward-compatible alias.
    static func paragraphs(fromHTML html: String) -> [String] {
        blocks(fromHTML: html)
    }
}
