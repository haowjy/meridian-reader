import Foundation

/// The spine's documents as one stream in reading order: positions across files, words between
/// any two positions, and the markup between them.
struct EPUBTextStream: Sendable {
    /// A place in the stream: before event `event` of spine document `document`. The end of a
    /// document is written as the start of the next, except at the end of the book.
    struct Position: Comparable, Hashable, Sendable {
        var document: Int
        var event: Int

        static func < (lhs: Position, rhs: Position) -> Bool {
            (lhs.document, lhs.event) < (rhs.document, rhs.event)
        }
    }

    let documents: [EPUBSpineDocument]
    /// Per document, words before each event (one more entry than events).
    private let wordsBefore: [[Int]]
    /// The same, counting only words outside front and back matter.
    private let bodyWordsBefore: [[Int]]
    /// Words before each document (one more entry than documents).
    private let documentWords: [Int]
    private let documentBodyWords: [Int]
    private let documentIndex: [String: Int]

    /// `bodyStart` and `backStart` come from landmarks or the guide: words before the body
    /// starts, and from where back matter starts, are front and back matter.
    init(documents: [EPUBSpineDocument], bodyStart: Position? = nil, backStart: Position? = nil) {
        self.documents = documents
        var wordsBefore: [[Int]] = []
        var bodyWordsBefore: [[Int]] = []
        var documentWords = [0]
        var documentBodyWords = [0]
        for (documentIndex, document) in documents.enumerated() {
            var all = [0]
            var body = [0]
            all.reserveCapacity(document.events.count + 1)
            body.reserveCapacity(document.events.count + 1)
            for event in document.events.indices {
                let position = Position(document: documentIndex, event: event)
                let words = document.words[event]
                let isMatter = document.inMarkedMatter[event]
                    || bodyStart.map { position < $0 } ?? false
                    || backStart.map { position >= $0 } ?? false
                all.append(all[event] + words)
                body.append(body[event] + (isMatter ? 0 : words))
            }
            wordsBefore.append(all)
            bodyWordsBefore.append(body)
            documentWords.append(documentWords[documentIndex] + all[document.events.count])
            documentBodyWords.append(documentBodyWords[documentIndex] + body[document.events.count])
        }
        self.wordsBefore = wordsBefore
        self.bodyWordsBefore = bodyWordsBefore
        self.documentWords = documentWords
        self.documentBodyWords = documentBodyWords
        var index: [String: Int] = [:]
        for (offset, document) in documents.enumerated() where index[document.path.lowercased()] == nil {
            index[document.path.lowercased()] = offset
        }
        documentIndex = index
    }

    var start: Position { normalized(Position(document: 0, event: 0)) }

    var end: Position {
        guard let last = documents.indices.last else { return Position(document: 0, event: 0) }
        return Position(document: last, event: documents[last].events.count)
    }

    var totalWords: Int { documentWords.last ?? 0 }

    /// The end of a document becomes the start of the next one.
    func normalized(_ position: Position) -> Position {
        var position = position
        while position.document < documents.count - 1, position.event >= documents[position.document].events.count {
            position = Position(document: position.document + 1, event: 0)
        }
        return position
    }

    func documentIndex(ofPath path: String) -> Int? {
        documentIndex[path.lowercased()]
    }

    /// Where an href lands: the element with the fragment's id, else the top of the file.
    /// Nil when the file isn't in the spine.
    func position(ofPath path: String, fragment: String?) -> Position? {
        guard let document = documentIndex(ofPath: path) else { return nil }
        let event = fragment.flatMap { documents[document].anchors[$0] } ?? 0
        return normalized(Position(document: document, event: event))
    }

    func words(from start: Position, to end: Position) -> Int {
        count(wordsBefore, documentWords, from: start, to: end)
    }

    /// Words in the range outside front and back matter.
    func bodyWords(from start: Position, to end: Position) -> Int {
        count(bodyWordsBefore, documentBodyWords, from: start, to: end)
    }

    private func count(_ perEvent: [[Int]], _ perDocument: [Int], from start: Position, to end: Position) -> Int {
        guard start < end, !documents.isEmpty else { return 0 }
        func before(_ position: Position) -> Int {
            guard position.document < documents.count else { return perDocument.last ?? 0 }
            return perDocument[position.document] + perEvent[position.document][position.event]
        }
        return before(end) - before(start)
    }

    /// Stable fragment for a position: its element's id, nil at the top of a file, else `@<event>`
    /// (`@` can't appear in an XML id, so it never collides with one). These go into chapter keys
    /// (the audio cache keys), so a change to `XHTMLReader` that numbers events differently
    /// changes the keys of chapters cut where no id is.
    func fragment(at position: Position) -> String? {
        guard position.event > 0 else { return nil }
        let document = documents[position.document]
        if position.event < document.events.count, case .open(let tag) = document.events[position.event],
           let id = tag.attribute("id"), !id.isEmpty {
            return id
        }
        return "@\(position.event)"
    }

    /// Spine files the range touches, in order.
    func paths(from start: Position, to end: Position) -> [String] {
        guard start < end else { return [] }
        let last = end.event == 0 && end.document > start.document ? end.document - 1 : end.document
        return (start.document...min(last, documents.count - 1)).map { documents[$0].path }
    }

    /// Open events in the range (from `start`, before `end`) of elements `include` accepts.
    func elementStarts(from start: Position, to end: Position, where include: (XHTMLTag) -> Bool) -> [Position] {
        positions(from: start, to: end) { event in
            if case .open(let tag) = event { return include(tag) }
            return false
        }
    }

    /// Text events in the range that continue a paragraph cut into runs.
    func runStarts(from start: Position, to end: Position) -> [Position] {
        guard start < end else { return [] }
        var found: [Position] = []
        for document in start.document...min(end.document, documents.count - 1) {
            let low = document == start.document ? start.event : 0
            let high = document == end.document ? end.event : documents[document].events.count
            found += documents[document].runStarts.filter { $0 >= low && $0 < high }
                .map { Position(document: document, event: $0) }
        }
        return found
    }

    /// Text events in the range.
    func textStarts(from start: Position, to end: Position) -> [Position] {
        positions(from: start, to: end) { event in
            if case .text = event { return true }
            return false
        }
    }

    private func positions(from start: Position, to end: Position,
                           where include: (XHTMLEvent) -> Bool) -> [Position] {
        guard start < end else { return [] }
        var found: [Position] = []
        for document in start.document...min(end.document, documents.count - 1) {
            let events = documents[document].events
            let low = document == start.document ? start.event : 0
            let high = document == end.document ? end.event : events.count
            guard low < high else { continue }
            for index in low..<high where include(events[index]) {
                found.append(Position(document: document, event: index))
            }
        }
        return found
    }
}

// MARK: - Markup between two positions

extension EPUBTextStream {
    /// Elements whose markup is never part of a chapter's XHTML.
    private static let droppedElements: Set<String> = ["script", "style", "link", "meta", "base", "title"]

    /// The markup between two positions as body-level XHTML. Elements the range starts inside are
    /// opened again at the top (with their attributes), and elements still open at the end are
    /// closed, the way a DOM range is cloned. A range across files joins each file's part.
    func xhtml(from start: Position, to end: Position) -> String {
        guard start < end else { return "" }
        var output = ""
        for documentIndex in start.document...min(end.document, documents.count - 1) {
            let document = documents[documentIndex]
            let low = documentIndex == start.document ? start.event : 0
            let high = documentIndex == end.document ? end.event : document.events.count
            guard low < high else { continue }
            var ancestors: [Int] = []
            var enclosing = document.parent[low]
            while enclosing >= 0 {
                ancestors.append(enclosing)
                enclosing = document.parent[enclosing]
            }
            var open: [String] = []
            for ancestor in ancestors.reversed() {
                guard case .open(let tag) = document.events[ancestor] else { continue }
                Self.writeOpen(tag, to: &output)
                open.append(tag.name)
            }
            var dropDepth = 0
            for event in document.events[low..<high] {
                switch event {
                case .open(let tag):
                    if dropDepth > 0 || Self.droppedElements.contains(tag.localName) {
                        dropDepth += 1
                        continue
                    }
                    Self.writeOpen(tag, to: &output)
                    open.append(tag.name)
                case .close:
                    if dropDepth > 0 {
                        dropDepth -= 1
                        continue
                    }
                    guard let name = open.popLast() else { continue }
                    Self.writeClose(name, to: &output)
                case .text(let text):
                    if dropDepth == 0 { output += XHTMLReader.escapeText(text) }
                }
            }
            while let name = open.popLast() {
                Self.writeClose(name, to: &output)
            }
            output += "\n"
        }
        return output
    }

    private static func writeOpen(_ tag: XHTMLTag, to output: inout String) {
        output += "<" + tag.name
        for attribute in tag.attributes {
            output += " " + attribute.name + "=\"" + XHTMLReader.escapeAttribute(attribute.value) + "\""
        }
        output += XHTMLReader.voidElements.contains(tag.localName) ? "/>" : ">"
    }

    private static func writeClose(_ name: String, to output: inout String) {
        guard !XHTMLReader.voidElements.contains(XHTMLTag.localName(of: name)) else { return }
        output += "</" + name + ">"
    }
}
