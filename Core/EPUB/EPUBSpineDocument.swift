import Foundation

/// One spine file, read for cutting: its body as balanced events, plus what the cutter asks of
/// it (where each id is, words per event, which events are front or back matter).
struct EPUBSpineDocument: Sendable {
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
    /// Per event: words in it (text events only).
    let words: [Int]
    /// Per event: inside front or back matter by the markup itself: `epub:type` frontmatter or
    /// backmatter, Gutenberg's header or licence, or a whole non-linear spine item.
    let inMarkedMatter: [Bool]
    /// Gutenberg's header and licence (`pg-boilerplate`, `pg-header`, `pg-footer`), each from its
    /// open event to just past its close. They become chapters of their own.
    let boilerplate: [Range<Int>]
    /// `linear="no"` in the spine (or the nav): an auxiliary page, which becomes a skipped
    /// chapter of its own.
    let linear: Bool
    /// Text events that continue a paragraph's text cut into runs (see `EPUBTextRuns`): the cut
    /// points inside a paragraph too long to keep whole.
    let runStarts: [Int]

    static let boilerplateMarkers: Set<String> = ["pg-boilerplate", "pg-header", "pg-footer", "pgheader", "pgfooter"]
    private static let matterTypes: Set<String> = ["frontmatter", "backmatter"]

    /// `maxRunWords`: text longer than this is cut into runs of at most this many words.
    init(path: String, data: Data, linear: Bool, maxRunWords: Int, budget: MarkupBudget) throws {
        self.path = path
        self.linear = linear
        let all = try XHTMLReader.events(from: data, budget: budget)
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
        var events: [XHTMLEvent] = []
        var runStarts: [Int] = []
        for event in bodyRange.map({ Array(all[$0]) }) ?? Self.withoutHead(all) {
            guard case .text(let text) = event, EPUBWordCount.count(text) > maxRunWords else {
                events.append(event)
                continue
            }
            for (offset, run) in EPUBTextRuns.split(text, maxWords: maxRunWords).enumerated() {
                if offset > 0 { runStarts.append(events.count) }
                events.append(.text(run))
            }
        }
        self.events = events
        self.runStarts = runStarts

        var parent = [Int](repeating: -1, count: events.count)
        var closing = [Int](repeating: -1, count: events.count)
        var anchors: [String: Int] = [:]
        var names: [String: Int] = [:]
        var words = [Int](repeating: 0, count: events.count)
        var marked = [Bool](repeating: false, count: events.count)
        var boilerplate: [Range<Int>] = []

        let baseMarked = !linear || !(bodyTag?.tokens(of: "epub:type").isDisjoint(with: Self.matterTypes) ?? true)
        // `inBoilerplate`: this element or one around it starts a boilerplate span.
        var stack: [(open: Int, marked: Bool, boilerplate: Bool, inBoilerplate: Bool)] = []
        for (index, event) in events.enumerated() {
            let enclosingMarked = stack.last?.marked ?? baseMarked
            switch event {
            case .open(let tag):
                parent[index] = stack.last?.open ?? -1
                if let id = tag.attribute("id"), anchors[id] == nil { anchors[id] = index }
                if tag.localName == "a", let name = tag.attribute("name"), names[name] == nil { names[name] = index }
                let enclosingBoilerplate = stack.last?.inBoilerplate ?? false
                let isBoilerplate = !enclosingBoilerplate && Self.isBoilerplate(tag)
                let isMarked = enclosingMarked || isBoilerplate
                    || !tag.tokens(of: "epub:type").isDisjoint(with: Self.matterTypes)
                marked[index] = isMarked
                stack.append((index, isMarked, isBoilerplate, enclosingBoilerplate || isBoilerplate))
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

/// Provisional word counts for cutting: counted on the raw XHTML's text events, before part 2's
/// normalizer turns it into listen blocks (which drops footnotes and the like, and doesn't split
/// a word that inline markup splits into two events). A word is a run of non-space characters
/// holding a letter or digit. Each Chinese or Japanese character counts as a word, since those
/// scripts don't put spaces between words.
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
                if isWordCharacter(scalar) { tokenHasWordCharacter = true }
            }
        }
        if inToken, tokenHasWordCharacter { count += 1 }
        return count
    }

    static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF: true
        default: false
        }
    }
}

/// Text too long to keep as one cut point, cut into runs: each ends after a sentence in its second
/// half where one ends there, else between words. A run boundary falls before the whitespace that
/// follows a word (or beside a Chinese or Japanese character), so the runs' word counts add up to
/// the text's and each run starts where a reader would pause.
enum EPUBTextRuns {
    /// Characters that end a sentence, and closing marks that may follow them.
    private static let sentenceEnds: Set<Unicode.Scalar> = [".", "!", "?", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let closingMarks: Set<Unicode.Scalar> = ["\"", "'", ")", "]", "\u{201D}", "\u{2019}", "\u{00BB}", "\u{300D}", "\u{300F}"]

    /// `text` as runs of at most `maxWords` words; joined, they are `text`.
    static func split(_ text: String, maxWords: Int) -> [String] {
        let scalars = Array(text.unicodeScalars)
        // Where a run may end: a scalar index, the words before it, and whether a sentence ends there.
        var boundaries: [(index: Int, words: Int, sentence: Bool)] = []
        var words = 0
        var inToken = false
        var tokenHasWord = false
        var tokenEndsSentence = false
        func endToken(at index: Int) {
            guard inToken else { return }
            if tokenHasWord { words += 1 }
            boundaries.append((index, words, tokenEndsSentence))
            inToken = false
            tokenHasWord = false
            tokenEndsSentence = false
        }
        for (index, scalar) in scalars.enumerated() {
            if scalar.properties.isWhitespace {
                endToken(at: index)
            } else if EPUBWordCount.isIdeographic(scalar) {
                endToken(at: index)
                words += 1
                boundaries.append((index + 1, words, false))
            } else {
                inToken = true
                if EPUBWordCount.isWordCharacter(scalar) { tokenHasWord = true }
                if sentenceEnds.contains(scalar) {
                    tokenEndsSentence = true
                } else if !closingMarks.contains(scalar) {
                    tokenEndsSentence = false
                }
            }
        }
        endToken(at: scalars.count)
        let total = words

        var cuts: [Int] = []
        var startWords = 0
        var next = 0
        while total - startWords > maxWords {
            let limit = startWords + maxWords
            var lastWord: Int?
            var lastSentence: Int?
            while next < boundaries.count, boundaries[next].words <= limit {
                let boundary = boundaries[next]
                if boundary.words > startWords {
                    lastWord = next
                    if boundary.sentence, boundary.words > startWords + maxWords / 2 { lastSentence = next }
                }
                next += 1
            }
            guard let chosen = lastSentence ?? lastWord else { break }
            cuts.append(boundaries[chosen].index)
            startWords = boundaries[chosen].words
            next = chosen + 1
        }
        guard !cuts.isEmpty else { return [text] }
        var runs: [String] = []
        var start = 0
        for cut in cuts + [scalars.count] where cut > start {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[start..<cut])
            runs.append(String(view))
            start = cut
        }
        return runs
    }
}
