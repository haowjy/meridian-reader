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
        collectDescendants(named: localName, into: &found)
        return found
    }

    private func collectDescendants(named localName: String, into found: inout [MarkupElement]) {
        for element in elements {
            if element.localName == localName { found.append(element) }
            element.collectDescendants(named: localName, into: &found)
        }
    }

    func firstDescendant(named localName: String) -> MarkupElement? {
        for element in elements {
            if element.localName == localName { return element }
            if let found = element.firstDescendant(named: localName) { return found }
        }
        return nil
    }

    /// All text below this element, with runs of whitespace collapsed to one space and trimmed.
    var text: String {
        var raw = ""
        appendText(to: &raw)
        return raw.collapsingWhitespace
    }

    private func appendText(to raw: inout String) {
        for child in children {
            switch child {
            case .text(let text): raw += text
            case .element(let element): element.appendText(to: &raw)
            }
        }
    }
}

indirect enum MarkupNode: Equatable, Sendable {
    case element(MarkupElement)
    case text(String)
}

/// Package documents (`container.xml`, the OPF, the NCX, `encryption.xml`): parsed with
/// `XMLParser`, and with the forgiving XHTML reader when they aren't well-formed XML.
enum XMLTree {
    /// The root element, or nil when the data holds no elements at all.
    static func parse(_ data: Data) -> MarkupElement? {
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        if parser.parse(), let root = builder.root {
            return root
        }
        return XHTMLReader.tree(from: data).elements.first
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [MarkupElement] = []
    private(set) var root: MarkupElement?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(MarkupElement(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard let element = stack.popLast() else { return }
        if stack.isEmpty {
            root = element
        } else {
            stack[stack.count - 1].children.append(.element(element))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    private func appendText(_ text: String) {
        guard !stack.isEmpty else { return }
        if case .text(let previous) = stack[stack.count - 1].children.last {
            stack[stack.count - 1].children[stack[stack.count - 1].children.count - 1] = .text(previous + text)
        } else {
            stack[stack.count - 1].children.append(.text(text))
        }
    }
}

extension String {
    /// Runs of whitespace (including newlines and no-break spaces) collapsed to one space, trimmed.
    var collapsingWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
