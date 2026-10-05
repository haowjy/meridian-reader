import Foundation

/// One spine file, read for cutting: its body as balanced events, plus what the cutter asks of
/// it (where each id is, its headings, words per event, which events are front or back matter).
struct EPUBSpineDocument: Sendable {
    struct Heading: Equatable, Sendable {
        var event: Int
        var level: Int
    }

    let path: String
    /// What's inside `<body>`, in order; opens and closes are balanced.
    let events: [XHTMLEvent]
    /// `xml:lang` or `lang` on `<html>` or `<body>`.
    let language: String?
    /// Per event: the open event of the innermost element open just before it (for a close,
    /// the element it closes); -1 at body level.
    let parent: [Int]
    /// Per open event: the index of its close; -1 for other events.
    let closing: [Int]
    /// `id` (or a legacy `<a name>`) → the open event of its element. The first one wins.
    let anchors: [String: Int]
    let headings: [Heading]
    /// Per event: words in it (text events only).
    let words: [Int]
    /// Per event: inside front or back matter by the markup itself: `epub:type` frontmatter or
    /// backmatter, Gutenberg's header or licence, or a whole non-linear spine item.
    let inMarkedMatter: [Bool]
    /// Gutenberg's header and licence (`pg-boilerplate`, `pg-header`, `pg-footer`), each from its
    /// open event to just past its close. They become chapters of their own.
    let boilerplate: [Range<Int>]

    static let boilerplateMarkers: Set<String> = ["pg-boilerplate", "pg-header", "pg-footer", "pgheader", "pgfooter"]
    private static let matterTypes: Set<String> = ["frontmatter", "backmatter"]

    init(path: String, data: Data, linear: Bool) {
        self.path = path
        let all = XHTMLReader.events(from: data)
        var language: String?
        var bodyRange: Range<Int>?
        var bodyTag: XHTMLTag?
        var depth = 0
        var bodyOpen: (index: Int, depth: Int)?
        for (index, event) in all.enumerated() {
            switch event {
            case .open(let tag):
                if tag.localName == "html" || tag.localName == "body" {
                    language = language ?? tag.attribute("xml:lang") ?? tag.attribute("lang")
                }
                if tag.localName == "body", bodyOpen == nil {
                    bodyOpen = (index, depth)
                    bodyTag = tag
                }
                depth += 1
            case .close:
                depth -= 1
                if let open = bodyOpen, bodyRange == nil, depth == open.depth {
                    bodyRange = (open.index + 1)..<index
                }
            case .text:
                break
            }
        }
        self.language = language?.isEmpty == false ? language : nil
        let events = bodyRange.map { Array(all[$0]) } ?? Self.withoutHead(all)
        self.events = events

        var parent = [Int](repeating: -1, count: events.count)
        var closing = [Int](repeating: -1, count: events.count)
        var anchors: [String: Int] = [:]
        var names: [String: Int] = [:]
        var headings: [Heading] = []
        var words = [Int](repeating: 0, count: events.count)
        var marked = [Bool](repeating: false, count: events.count)
        var boilerplate: [Range<Int>] = []

        let baseMarked = !linear || !(bodyTag?.tokens(of: "epub:type").isDisjoint(with: Self.matterTypes) ?? true)
        var stack: [(open: Int, marked: Bool, boilerplate: Bool)] = []
        for (index, event) in events.enumerated() {
            let enclosingMarked = stack.last?.marked ?? baseMarked
            switch event {
            case .open(let tag):
                parent[index] = stack.last?.open ?? -1
                if let id = tag.attribute("id"), anchors[id] == nil { anchors[id] = index }
                if tag.localName == "a", let name = tag.attribute("name"), names[name] == nil { names[name] = index }
                if let level = Self.headingLevel(tag.localName) { headings.append(Heading(event: index, level: level)) }
                let isBoilerplate = Self.isBoilerplate(tag) && !stack.contains { $0.boilerplate }
                let isMarked = enclosingMarked || isBoilerplate
                    || !tag.tokens(of: "epub:type").isDisjoint(with: Self.matterTypes)
                marked[index] = isMarked
                stack.append((index, isMarked, isBoilerplate))
            case .close:
                guard let open = stack.popLast() else { continue }
                parent[index] = open.open
                closing[open.open] = index
                marked[index] = open.marked
                if open.boilerplate { boilerplate.append(open.open..<(index + 1)) }
            case .text(let text):
                parent[index] = stack.last?.open ?? -1
                words[index] = EPUBWordCount.count(text)
                marked[index] = enclosingMarked
            }
        }
        for (name, index) in names where anchors[name] == nil { anchors[name] = index }

        self.parent = parent
        self.closing = closing
        self.anchors = anchors
        self.headings = headings
        self.words = words
        self.inMarkedMatter = marked
        self.boilerplate = boilerplate
    }

    /// The text of the element opened at `event`, whitespace collapsed.
    func text(ofElementAt event: Int) -> String {
        guard event < events.count, closing[event] > event else { return "" }
        return events[(event + 1)..<closing[event]].textContent.collapsingWhitespace
    }

    // MARK: - Helpers

    static func headingLevel(_ localName: String) -> Int? {
        guard localName.count == 2, localName.hasPrefix("h"), let level = Int(localName.dropFirst()),
              (1...6).contains(level) else { return nil }
        return level
    }

    private static func isBoilerplate(_ tag: XHTMLTag) -> Bool {
        var markers = tag.tokens(of: "class")
        if let id = tag.attribute("id") { markers.insert(id.lowercased()) }
        return !markers.isDisjoint(with: boilerplateMarkers)
    }

    /// A document without `<body>`: everything but `<head>` and the `<html>` wrapper.
    private static func withoutHead(_ events: [XHTMLEvent]) -> [XHTMLEvent] {
        var kept: [XHTMLEvent] = []
        var skipping = 0
        var htmlDepth: [Bool] = []
        for event in events {
            switch event {
            case .open(let tag):
                if skipping > 0 || tag.localName == "head" {
                    skipping += 1
                    htmlDepth.append(false)
                    continue
                }
                let isWrapper = tag.localName == "html"
                htmlDepth.append(isWrapper)
                if !isWrapper { kept.append(event) }
            case .close:
                let isWrapper = htmlDepth.popLast() ?? false
                if skipping > 0 {
                    skipping -= 1
                    continue
                }
                if !isWrapper { kept.append(event) }
            case .text:
                if skipping == 0 { kept.append(event) }
            }
        }
        return kept
    }
}

extension Collection where Element == XHTMLEvent {
    /// The text events joined, as written.
    var textContent: String {
        reduce(into: "") { result, event in
            if case .text(let text) = event { result += text }
        }
    }
}

/// Word counts for cutting thresholds: a word is a run of non-space characters holding a letter
/// or digit. Each Chinese or Japanese character counts as a word, since those scripts don't put
/// spaces between words.
enum EPUBWordCount {
    static func count(_ text: String) -> Int {
        var count = 0
        var inToken = false
        var tokenHasWordCharacter = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if inToken, tokenHasWordCharacter { count += 1 }
                inToken = false
                tokenHasWordCharacter = false
            } else if isIdeographic(scalar) {
                if inToken, tokenHasWordCharacter { count += 1 }
                count += 1
                inToken = false
                tokenHasWordCharacter = false
            } else {
                inToken = true
                if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                    tokenHasWordCharacter = true
                }
            }
        }
        if inToken, tokenHasWordCharacter { count += 1 }
        return count
    }

    private static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF: true
        default: false
        }
    }
}
