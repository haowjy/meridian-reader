import Foundation

/// A parsed XML or XHTML element: just what the package and contents readers need.
struct MarkupElement: Equatable, Sendable {
    /// As written, with any prefix (`dc:title`).
    var name: String
    /// Lowercased, prefix dropped (`title`).
    var localName: String
    /// Keys as written (`epub:type`, `opf:role`).
    var attributes: [String: String]
    var children: [MarkupNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.localName = XHTMLTag.localName(of: name)
        self.attributes = attributes
    }

    /// The attribute named exactly `name`, ignoring ASCII case.
    func attribute(_ name: String) -> String? {
        if let value = attributes[name] { return value }
        return attributes.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Whitespace-separated, lowercased tokens of an attribute such as `epub:type` or `properties`.
    func tokens(of attributeName: String) -> Set<String> {
        guard let value = attribute(attributeName) else { return [] }
        return Set(value.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
    }

    var elements: [MarkupElement] {
        children.compactMap {
            if case .element(let element) = $0 { return element }
            return nil
        }
    }

    /// Direct children with this local name.
    func elements(named localName: String) -> [MarkupElement] {
        elements.filter { $0.localName == localName }
    }

    func firstElement(named localName: String) -> MarkupElement? {
        elements.first { $0.localName == localName }
    }

    /// Every element below this one with this local name, in document order.
    func descendants(named localName: String) -> [MarkupElement] {
        var found: [MarkupElement] = []
        var pending = Array(elements.reversed())
        while let element = pending.popLast() {
            if element.localName == localName { found.append(element) }
            pending.append(contentsOf: element.elements.reversed())
        }
        return found
    }

    func firstDescendant(named localName: String) -> MarkupElement? {
        var pending = Array(elements.reversed())
        while let element = pending.popLast() {
            if element.localName == localName { return element }
            pending.append(contentsOf: element.elements.reversed())
        }
        return nil
    }

    /// All text below this element, with runs of whitespace collapsed to one space and trimmed.
    var text: String {
        var raw = ""
        var pending = Array(children.reversed())
        while let node = pending.popLast() {
            switch node {
            case .text(let text): raw += text
            case .element(let element): pending.append(contentsOf: element.children.reversed())
            }
        }
        return raw.collapsingWhitespace
    }
}

/// A tree is only as deep as `EPUBLimits.maxNestingDepth`, which both parsers enforce, so
/// releasing one (recursive, as Swift values are) stays shallow.
indirect enum MarkupNode: Equatable, Sendable {
    case element(MarkupElement)
    case text(String)
}

/// Package documents (`container.xml`, the OPF, the NCX, `encryption.xml`, Apple's display
/// options), parsed strictly with `XMLParser`. These are machine-written XML; one that isn't
/// well-formed is refused rather than guessed at, and so is one that declares entities: no
/// entity is expanded and nothing outside the archive is resolved. A doctype that only names an
/// external DTD (the NCX's, OEB 1.2's) declares nothing and is read; the DTD isn't fetched.
enum XMLTree {
    /// The root element. Throws `.unreadable` when the XML isn't well-formed, has no element, or
    /// declares an entity; `.tooLarge` past the budget's caps.
    static func parse(_ data: Data, named name: String, budget: MarkupBudget) throws -> MarkupElement {
        if declaresEntities(data) { throw EPUBError.unreadable("\(name) declares entities") }
        let builder = XMLTreeBuilder(counter: budget.counter())
        let parser = makeParser(data)
        parser.delegate = builder
        let parsed = parser.parse()
        if let error = builder.error { throw error }
        guard parsed, let root = builder.root else { throw EPUBError.unreadable("\(name) isn't well-formed XML") }
        return root
    }

    /// An `XMLParser` that resolves no external entity (DTDs included) and reports no namespaces.
    static func makeParser(_ data: Data) -> XMLParser {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        return parser
    }

    /// Whether the document declares an entity: `<!ENTITY` as markup (any letter case), in the
    /// doctype's internal subset or anywhere else. Comments, CDATA sections, processing
    /// instructions and quoted literals are stepped over the way XML reads them, so a document
    /// that only mentions `<!ENTITY` inside one isn't refused. Checked before parsing, so no
    /// internal entity (a billion-laughs chain among them) is ever expanded.
    static func declaresEntities(_ data: Data) -> Bool {
        var scanner = EntityDeclarationScanner(characters: asciiCharacters(of: data))
        return scanner.findsDeclaration()
    }

    /// The document's characters, one byte each: ASCII as itself, anything else as 0x80. Markup is
    /// all ASCII, so this is enough to find it. UTF-32 and UTF-16 are told by their byte-order
    /// mark or by how the first character is written; any other encoding is read byte by byte,
    /// which keeps ASCII where it is in UTF-8 and the single-byte encodings.
    private static func asciiCharacters(of data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        let head = Array(bytes.prefix(4)) + Array(repeating: 0xFF, count: max(0, 4 - bytes.count))
        let width: Int
        let bigEndian: Bool
        if head == [0x00, 0x00, 0xFE, 0xFF] || head[0...2] == [0x00, 0x00, 0x00] && head[3] != 0 {
            (width, bigEndian) = (4, true)
        } else if head == [0xFF, 0xFE, 0x00, 0x00] || head[0] != 0 && head[1...3] == [0x00, 0x00, 0x00] {
            (width, bigEndian) = (4, false)
        } else if head[0...1] == [0xFE, 0xFF] || head[0] == 0 && head[1] != 0 {
            (width, bigEndian) = (2, true)
        } else if head[0...1] == [0xFF, 0xFE] || head[0] != 0 && head[1] == 0 {
            (width, bigEndian) = (2, false)
        } else {
            return bytes
        }
        var characters: [UInt8] = []
        characters.reserveCapacity(bytes.count / width)
        var index = 0
        while index + width <= bytes.count {
            var unit: UInt32 = 0
            for offset in 0..<width {
                unit = unit << 8 | UInt32(bytes[index + (bigEndian ? offset : width - 1 - offset)])
            }
            characters.append(unit < 0x80 ? UInt8(unit) : 0x80)
            index += width
        }
        return characters
    }
}

/// Finds an entity declaration the way an XML parser would meet one: at the top level of the
/// document or of a doctype's internal subset, never inside a comment, CDATA section, processing
/// instruction or quoted literal. Linear in the document's length.
private struct EntityDeclarationScanner {
    let characters: [UInt8]
    var index = 0

    mutating func findsDeclaration() -> Bool {
        while index < characters.count {
            guard characters[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            if matches("<!--") {
                skip(past: "-->")
            } else if matches("<![CDATA[") {
                skip(past: "]]>")
            } else if matches("<?") {
                skip(past: "?>")
            } else if matches("<!ENTITY", ignoringCase: true) {
                return true
            } else if startsTagOrDeclaration() {
                skipTagOrDeclaration()
            } else {
                // `<![INCLUDE[` and the like: what follows is read as markup.
                index += 1
            }
        }
        return false
    }

    /// `<` then a name (or `/`), or `<!` then a keyword (`DOCTYPE`, `ELEMENT`, …).
    private func startsTagOrDeclaration() -> Bool {
        guard index + 1 < characters.count else { return false }
        let next = characters[index + 1]
        if next == UInt8(ascii: "!") {
            return index + 2 < characters.count && isLetter(characters[index + 2])
        }
        return isLetter(next) || next == UInt8(ascii: "/") || next == UInt8(ascii: "_")
            || next == UInt8(ascii: ":") || next >= 0x80
    }

    /// From the `<`: past the closing `>`, stepping over quoted literals. Stops before a `[` (a
    /// doctype's internal subset, whose declarations are scanned as markup again) and before a
    /// `<` (the tag wasn't closed, and the `<` starts new markup).
    private mutating func skipTagOrDeclaration() {
        index += 1
        var quote: UInt8?
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == UInt8(ascii: "\"") || character == UInt8(ascii: "'") {
                quote = character
            } else if character == UInt8(ascii: ">") {
                index += 1
                return
            } else if character == UInt8(ascii: "[") || character == UInt8(ascii: "<") {
                return
            }
            index += 1
        }
    }

    /// Past the next `terminator`, or to the end when there's none.
    private mutating func skip(past terminator: String) {
        let pattern = Array(terminator.utf8)
        while index < characters.count, !matches(pattern, ignoringCase: false) {
            index += 1
        }
        index = min(characters.count, index + pattern.count)
    }

    /// What's stepped over matches exactly, as XML spells it; a declaration matches in any case,
    /// so a lookalike is refused rather than stepped over.
    private func matches(_ text: String, ignoringCase: Bool = false) -> Bool {
        matches(Array(text.utf8), ignoringCase: ignoringCase)
    }

    private func matches(_ pattern: [UInt8], ignoringCase: Bool) -> Bool {
        guard index + pattern.count <= characters.count else { return false }
        for offset in pattern.indices {
            let character = characters[index + offset]
            let expected = pattern[offset]
            guard character == expected || ignoringCase && lowercased(character) == lowercased(expected) else {
                return false
            }
        }
        return true
    }

    private func lowercased(_ character: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(character) ? character + 32 : character
    }

    private func isLetter(_ character: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(lowercased(character))
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private var counter: MarkupCounter
    private var stack: [MarkupElement] = []
    /// Text since the last tag, appended to the open element at the next tag.
    private var pendingText = ""
    private(set) var root: MarkupElement?
    private(set) var error: EPUBError?

    init(counter: MarkupCounter) {
        self.counter = counter
    }

    private func stop(_ parser: XMLParser, _ error: EPUBError) {
        guard self.error == nil else { return }
        self.error = error
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard error == nil else { return }
        do {
            try counter.countNodes(1 + attributeDict.count)
            try counter.checkDepth(stack.count + 1)
        } catch {
            return stop(parser, error as? EPUBError ?? .tooLarge)
        }
        flushText()
        stack.append(MarkupElement(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard error == nil else { return }
        flushText()
        guard let element = stack.popLast() else { return }
        if stack.isEmpty {
            root = element
        } else {
            stack[stack.count - 1].children.append(.element(element))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string, parser)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self), parser)
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        stop(parser, .unreadable("declares the entity \(name)"))
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?,
                systemID: String?) {
        stop(parser, .unreadable("declares the entity \(name)"))
    }

    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?,
                systemID: String?, notationName: String?) {
        stop(parser, .unreadable("declares the entity \(name)"))
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        stop(parser, .unreadable("refers to the external entity \(name)"))
        return nil
    }

    private func appendText(_ text: String, _ parser: XMLParser) {
        guard error == nil, !stack.isEmpty else { return }
        if pendingText.isEmpty {
            do {
                try counter.countNodes()
            } catch {
                return stop(parser, error as? EPUBError ?? .tooLarge)
            }
        }
        pendingText += text
    }

    private func flushText() {
        guard !pendingText.isEmpty, !stack.isEmpty else { return }
        stack[stack.count - 1].children.append(.text(pendingText))
        pendingText = ""
    }
}

extension String {
    /// Runs of whitespace (including newlines and no-break spaces) collapsed to one space, trimmed.
    var collapsingWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
