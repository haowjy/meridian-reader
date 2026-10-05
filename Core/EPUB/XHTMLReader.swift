import Foundation

/// A start tag as written: its name, local name (lowercased, prefix dropped) and attributes.
struct XHTMLTag: Equatable, Sendable {
    var name: String
    var localName: String
    var attributes: [XHTMLAttribute]

    init(name: String, attributes: [XHTMLAttribute] = []) {
        self.name = name
        self.localName = XHTMLTag.localName(of: name)
        self.attributes = attributes
    }

    /// The value of the attribute named exactly `name` (ASCII case-insensitive), e.g. `"epub:type"`.
    func attribute(_ name: String) -> String? {
        attributes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Whitespace-separated tokens of an attribute such as `class` or `epub:type`.
    func tokens(of attributeName: String) -> Set<String> {
        guard let value = attribute(attributeName) else { return [] }
        return Set(value.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
    }

    static func localName(of qualifiedName: String) -> String {
        let local = qualifiedName.split(separator: ":").last.map(String.init) ?? qualifiedName
        return local.lowercased()
    }
}

struct XHTMLAttribute: Equatable, Sendable {
    var name: String
    var value: String
}

/// One step of a document in reading order. Opens and closes are always balanced.
enum XHTMLEvent: Equatable, Sendable {
    case open(XHTMLTag)
    case close(name: String)
    case text(String)
}

/// A forgiving reader for EPUB content and navigation documents.
///
/// XHTML in real EPUBs is meant to be well-formed XML, but HTML named entities (`&nbsp;`,
/// `&mdash;`) and the odd stray tag are common, and `XMLParser` gives up at the first one. This
/// reader accepts any markup within the budget's caps: it decodes entities, skips comments,
/// doctypes and processing instructions, drops `script` and `style` contents, and balances tags
/// (a stray end tag is ignored; an end tag closes whatever it implies; anything open at the end
/// is closed). Past a cap (file size is checked when the file is read; nodes and nesting here)
/// it throws `EPUBError.tooLarge`. Work is linear in the file's size.
enum XHTMLReader {
    /// Elements that never have content, written `<br/>`.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr",
    ]

    /// Elements whose content is code, not text; their content is dropped.
    private static let rawTextElements: Set<String> = ["script", "style"]

    static func events(from data: Data, budget: MarkupBudget) throws -> [XHTMLEvent] {
        var tokenizer = Tokenizer(bytes: utf8Bytes(of: data), counter: budget.counter())
        return try tokenizer.run()
    }

    /// The document as an element tree, for navigation documents and cover pages. Top-level
    /// text is dropped; the root holds the top-level elements.
    static func tree(from data: Data, budget: MarkupBudget) throws -> MarkupElement {
        tree(from: try events(from: data, budget: budget))
    }

    static func tree(from events: [XHTMLEvent]) -> MarkupElement {
        var stack = [MarkupElement(name: "#document", attributes: [:])]
        for event in events {
            switch event {
            case .open(let tag):
                var attributes: [String: String] = [:]
                for attribute in tag.attributes where attributes[attribute.name] == nil {
                    attributes[attribute.name] = attribute.value
                }
                stack.append(MarkupElement(name: tag.name, attributes: attributes))
            case .close:
                guard stack.count > 1, let element = stack.popLast() else { continue }
                stack[stack.count - 1].children.append(.element(element))
            case .text(let text):
                guard stack.count > 1 else { continue }
                stack[stack.count - 1].children.append(.text(text))
            }
        }
        while stack.count > 1, let element = stack.popLast() {
            stack[stack.count - 1].children.append(.element(element))
        }
        return stack[0]
    }

    /// UTF-8 bytes of a document that may be UTF-8 (with or without a BOM) or UTF-16 with a BOM.
    private static func utf8Bytes(of data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return Array(bytes.dropFirst(3)) }
        if bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) {
            let text = String(data: data, encoding: .utf16) ?? ""
            return Array(text.utf8)
        }
        return bytes
    }

    // MARK: - Tokenizer

    private struct Tokenizer {
        let bytes: [UInt8]
        var counter: MarkupCounter
        var index = 0
        var events: [XHTMLEvent] = []
        /// Open elements, innermost last.
        var open: [(name: String, localName: String)] = []
        /// How many open elements have each local name, so an end tag that matches none is
        /// ignored without searching `open`.
        var openCounts: [String: Int] = [:]
        /// Text since the last tag, written as one event at the next tag (or the end).
        var pendingText = ""

        init(bytes: [UInt8], counter: MarkupCounter) {
            self.bytes = bytes
            self.counter = counter
        }

        mutating func run() throws -> [XHTMLEvent] {
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "<") {
                    try readMarkup()
                } else {
                    readText()
                }
            }
            try flushText()
            while let element = open.popLast() {
                events.append(.close(name: element.name))
            }
            return events
        }

        // MARK: Text

        mutating func readText() {
            let start = index
            while index < bytes.count, bytes[index] != UInt8(ascii: "<") { index += 1 }
            appendText(XHTMLReader.decodeEntities(String(decoding: bytes[start..<index], as: UTF8.self)))
        }

        /// Text outside every element is dropped.
        mutating func appendText(_ text: String) {
            guard !open.isEmpty else { return }
            pendingText += text
        }

        mutating func flushText() throws {
            guard !pendingText.isEmpty else { return }
            try counter.countNodes()
            events.append(.text(pendingText))
            pendingText = ""
        }

        mutating func push(_ name: String, _ localName: String) throws {
            try counter.checkDepth(open.count + 1)
            open.append((name, localName))
            openCounts[localName, default: 0] += 1
        }

        // MARK: Markup

        mutating func readMarkup() throws {
            if hasPrefix("<!--") {
                try counter.countNodes()
                skip(past: "-->")
            } else if hasPrefix("<![CDATA[") {
                index += 9
                let start = index
                let end = find("]]>") ?? bytes.count
                appendText(String(decoding: bytes[start..<end], as: UTF8.self))
                index = min(end + 3, bytes.count)
            } else if hasPrefix("<!") {
                try counter.countNodes()
                skipDeclaration()
            } else if hasPrefix("<?") {
                try counter.countNodes()
                skip(past: "?>")
            } else if hasPrefix("</") {
                try readEndTag()
            } else if index + 1 < bytes.count, isNameStart(bytes[index + 1]) {
                try readStartTag()
            } else {
                index += 1
                appendText("<")
            }
        }

        mutating func readStartTag() throws {
            index += 1
            let name = readName()
            var attributes: [XHTMLAttribute] = []
            var selfClosing = false
            while index < bytes.count {
                skipWhitespace()
                guard index < bytes.count else { break }
                let byte = bytes[index]
                if byte == UInt8(ascii: ">") {
                    index += 1
                    break
                }
                if byte == UInt8(ascii: "/") {
                    index += 1
                    if index < bytes.count, bytes[index] == UInt8(ascii: ">") {
                        selfClosing = true
                        index += 1
                        break
                    }
                    continue
                }
                let attributeName = readName()
                guard !attributeName.isEmpty else {
                    index += 1
                    continue
                }
                skipWhitespace()
                var value = ""
                if index < bytes.count, bytes[index] == UInt8(ascii: "=") {
                    index += 1
                    skipWhitespace()
                    value = readAttributeValue()
                }
                try counter.countNodes()
                attributes.append(XHTMLAttribute(name: attributeName, value: value))
            }
            try counter.countNodes()
            try flushText()
            let tag = XHTMLTag(name: name, attributes: attributes)
            events.append(.open(tag))
            if selfClosing || XHTMLReader.voidElements.contains(tag.localName) {
                events.append(.close(name: name))
            } else if XHTMLReader.rawTextElements.contains(tag.localName) {
                skipRawText(until: tag.localName)
                events.append(.close(name: name))
            } else {
                try push(name, tag.localName)
            }
        }

        /// Closes the innermost open element with the end tag's local name, and every element
        /// inside it; ignored when none is open. Each element is closed once, so this is
        /// amortized constant time.
        mutating func readEndTag() throws {
            index += 2
            let name = readName()
            skip(past: ">")
            try counter.countNodes()
            let local = XHTMLTag.localName(of: name)
            guard openCounts[local, default: 0] > 0 else { return }
            try flushText()
            while let element = open.popLast() {
                openCounts[element.localName, default: 1] -= 1
                events.append(.close(name: element.name))
                if element.localName == local { break }
            }
        }

        mutating func readAttributeValue() -> String {
            guard index < bytes.count else { return "" }
            let quote = bytes[index]
            if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                index += 1
                let start = index
                while index < bytes.count, bytes[index] != quote { index += 1 }
                let raw = String(decoding: bytes[start..<index], as: UTF8.self)
                index = min(index + 1, bytes.count)
                return XHTMLReader.decodeEntities(raw)
            }
            let start = index
            while index < bytes.count, !isWhitespace(bytes[index]), bytes[index] != UInt8(ascii: ">") {
                index += 1
            }
            return XHTMLReader.decodeEntities(String(decoding: bytes[start..<index], as: UTF8.self))
        }

        mutating func readName() -> String {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if isWhitespace(byte) || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "/")
                    || byte == UInt8(ascii: "=") {
                    break
                }
                index += 1
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        /// `<!DOCTYPE …>`, possibly with an internal subset in brackets.
        mutating func skipDeclaration() {
            var inSubset = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == UInt8(ascii: "[") { inSubset = true }
                if byte == UInt8(ascii: "]") { inSubset = false }
                if byte == UInt8(ascii: ">"), !inSubset { return }
            }
        }

        mutating func skipRawText(until localName: String) {
            let closing = Array("</\(localName)".utf8)
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "<"), matchesIgnoringCase(closing, at: index) {
                    skip(past: ">")
                    return
                }
                index += 1
            }
        }

        // MARK: Scanning helpers

        func hasPrefix(_ prefix: String) -> Bool {
            matchesIgnoringCase(Array(prefix.utf8), at: index)
        }

        func matchesIgnoringCase(_ pattern: [UInt8], at position: Int) -> Bool {
            guard position + pattern.count <= bytes.count else { return false }
            for offset in 0..<pattern.count where lower(bytes[position + offset]) != lower(pattern[offset]) {
                return false
            }
            return true
        }

        func find(_ pattern: String) -> Int? {
            let needle = Array(pattern.utf8)
            var position = index
            while position + needle.count <= bytes.count {
                if bytes[position] == needle[0], needle.indices.allSatisfy({ bytes[position + $0] == needle[$0] }) {
                    return position
                }
                position += 1
            }
            return nil
        }

        mutating func skip(past pattern: String) {
            if let end = find(pattern) {
                index = end + pattern.utf8.count
            } else {
                index = bytes.count
            }
        }

        mutating func skipWhitespace() {
            while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
        }

        func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        }

        func isNameStart(_ byte: UInt8) -> Bool {
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == UInt8(ascii: "_")
                || byte == UInt8(ascii: ":") || byte >= 0x80
        }

        func lower(_ byte: UInt8) -> UInt8 {
            (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
        }
    }

    // MARK: - Entities

    /// Decodes numeric references and the named entities books use. An unknown name stays as written.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let afterAmp = rest.index(after: amp)
            let limit = rest.index(afterAmp, offsetBy: 32, limitedBy: rest.endIndex) ?? rest.endIndex
            guard let semicolon = rest[afterAmp..<limit].firstIndex(of: ";"),
                  let decoded = decodeEntity(rest[afterAmp..<semicolon]) else {
                result += "&"
                rest = rest[afterAmp...]
                continue
            }
            result += decoded
            rest = rest[rest.index(after: semicolon)...]
        }
        result += rest
        return result
    }

    private static func decodeEntity(_ name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[String(name)].map { String(Character($0)) }
    }

    /// XML's five, Latin-1 (160–255) and the punctuation and symbols common in books.
    private static let namedEntities: [String: Unicode.Scalar] = {
        var table: [String: Unicode.Scalar] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}",
            "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}", "ndash": "\u{2013}",
            "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
            "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "dagger": "\u{2020}",
            "Dagger": "\u{2021}", "bull": "\u{2022}", "hellip": "\u{2026}", "permil": "\u{2030}",
            "prime": "\u{2032}", "Prime": "\u{2033}", "lsaquo": "\u{2039}", "rsaquo": "\u{203A}",
            "oline": "\u{203E}", "frasl": "\u{2044}", "euro": "\u{20AC}", "trade": "\u{2122}",
            "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}",
            "harr": "\u{2194}", "minus": "\u{2212}", "OElig": "\u{0152}", "oelig": "\u{0153}",
            "Scaron": "\u{0160}", "scaron": "\u{0161}", "Yuml": "\u{0178}", "fnof": "\u{0192}",
            "circ": "\u{02C6}", "tilde": "\u{02DC}", "alpha": "\u{03B1}", "beta": "\u{03B2}",
            "gamma": "\u{03B3}", "delta": "\u{03B4}", "pi": "\u{03C0}", "sigma": "\u{03C3}",
            "omega": "\u{03C9}", "hearts": "\u{2665}", "loz": "\u{25CA}",
        ]
        let latin1 = """
        nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn \
        sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave \
        Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml \
        ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN \
        szlig agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute \
        icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml \
        yacute thorn yuml
        """
        for (offset, name) in latin1.split(separator: " ").enumerated() {
            table[String(name)] = Unicode.Scalar(UInt32(160 + offset))
        }
        return table
    }()

    // MARK: - Writing

    /// Text escaped for element content.
    static func escapeText(_ text: String) -> String {
        guard text.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" }) else { return text }
        return text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Text escaped for a double-quoted attribute value.
    static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
