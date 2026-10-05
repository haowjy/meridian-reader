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
/// entity is expanded and nothing outside the archive is resolved.
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

    /// An `<!ENTITY` declaration anywhere, in UTF-8 or UTF-16. Checked before parsing, so no
    /// internal entity (a billion-laughs chain among them) is ever expanded.
    static func declaresEntities(_ data: Data) -> Bool {
        let declaration = "<!ENTITY"
        let patterns = [Data(declaration.utf8), declaration.data(using: .utf16LittleEndian),
                        declaration.data(using: .utf16BigEndian)].compactMap { $0 }
        return patterns.contains { data.range(of: $0) != nil }
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
