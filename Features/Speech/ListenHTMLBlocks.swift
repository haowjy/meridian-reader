import Foundation

/// Single source of truth for which HTML elements are listen / highlight / tap units.
/// Swift extraction and HTMLReadingView JS both use `tags` / `innerSelector`.
enum ListenHTMLBlocks {
    /// Document-order speakable tags. Prefer nested leaves (e.g. `<p>` inside `<blockquote>`)
    /// over the wrapper so text is not spoken twice.
    static let tags: [String] = [
        "h1", "h2", "h3", "h4", "h5", "h6",
        "p",
        "li",
        "blockquote",
        "pre",
        "figcaption",
        "td", "th",
        "dt", "dd",
    ]

    /// Bump whenever the block rules or text extraction change. Saved articles store their
    /// paragraphs with this number and rebuild once when it no longer matches.
    /// v3 (2026-09-25): giant paragraphs are split at sentence ends (`splitLongBlocks`).
    static let version = 3

    /// CSS selector for `querySelectorAll` / `querySelector` inside the article body.
    static var innerSelector: String {
        tags.joined(separator: ", ")
    }

    /// Non-empty leaf block plain texts in document order.
    ///
    /// Same rule as the HTMLReadingView JS: an element whose tag is in `tags`, that contains
    /// no nested `tags` element, and whose trimmed text is non-empty.
    ///
    /// One forward pass over the UTF-8 bytes (O(n) in HTML length): a small stack of open
    /// listen tags, a shared text buffer, and inline entity decoding. No regex, no
    /// per-`Character` walking, no pairwise leaf filtering.
    static func leafTexts(fromHTML html: String) -> [String] {
        var html = html
        return html.withUTF8 { ListenBlockScanner.scan($0) }
    }

    /// Leaf tags whose giant text may be split into several sibling elements of the same tag
    /// (p, blockquote, dd). Headings, list items, table cells, pre and captions stay whole.
    static let splittableTags: Set<String> = ["p", "blockquote", "dd"]

    /// Split leaf blocks longer than `ParagraphSplitter.threshold` at sentence ends into sibling
    /// elements (same tag + attributes minus `id`; inline tags open at the cut are closed and
    /// reopened). Deterministic; `leafTexts(splitLongBlocks(h)) == leafTexts(h).flatMap(pieces)`
    /// for splittable leaves (unit-tested). Returns `html` unchanged when nothing is split.
    static func splitLongBlocks(_ html: String) -> String {
        var html = html
        return html.withUTF8 { buf -> String? in
            let leaves = ListenBlockScanner.scanLeaves(buf)
            var inserts: [(pos: Int, text: [UInt8])] = []
            for leaf in leaves where splittableTags.contains(leaf.tagName) {
                let offsets = ParagraphSplitter.pieceStartUTF8Offsets(leaf.text)
                guard !offsets.isEmpty else { continue }
                let openTag = ListenBlockScanner.openTagWithoutID(buf, leaf.openStart, leaf.openEnd)
                for off in offsets where off < leaf.source.count {
                    let pos = leaf.source[off]
                    let stack = ListenBlockScanner.inlineStack(buf, from: leaf.openEnd, to: pos)
                    var brk: [UInt8] = []
                    for t in stack.reversed() { brk += Array("</\(t.name)>".utf8) }
                    brk += Array("</\(leaf.tagName)>".utf8)
                    brk += openTag
                    for t in stack { brk += t.raw }
                    inserts.append((pos, brk))
                }
            }
            guard !inserts.isEmpty else { return nil }
            inserts.sort { $0.pos < $1.pos }
            var out: [UInt8] = []
            out.reserveCapacity(buf.count + inserts.reduce(0) { $0 + $1.text.count })
            var cursor = 0
            for ins in inserts {
                out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[cursor..<ins.pos]))
                out.append(contentsOf: ins.text)
                cursor = ins.pos
            }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[cursor..<buf.count]))
            return String(decoding: out, as: UTF8.self)
        } ?? html
    }
}

// MARK: - Byte scanner

private enum ListenBlockScanner {
    // Tag ids. 1...15 are listen tags (h1-h6, p, li, blockquote, pre, figcaption, td, th, dt, dd).
    // Keep in sync with `ListenHTMLBlocks.tags`.
    private static let none: UInt8 = 0
    private static let br: UInt8 = 20
    private static let script: UInt8 = 30
    private static let style: UInt8 = 31

    private struct Frame {
        var tag: UInt8
        var hasBlockChild: Bool
        var textStart: Int
        var openStart: Int = 0
        var openEnd: Int = 0
    }

    /// A leaf listen block with source positions (for `splitLongBlocks`).
    struct Leaf {
        var tagName: String
        var text: String
        /// Byte range of the opening tag `<p ...>`.
        var openStart: Int
        var openEnd: Int
        /// For each UTF-8 byte of `text`, the source byte it came from (entity start for entities).
        var source: [Int]
    }

    private static let tagNames: [UInt8: String] = [
        1: "h1", 2: "h2", 3: "h3", 4: "h4", 5: "h5", 6: "h6", 7: "p", 8: "li", 9: "blockquote",
        10: "pre", 11: "td", 12: "th", 13: "dt", 14: "dd", 15: "figcaption",
    ]

    private static let lt: UInt8 = 0x3C      // <
    private static let gt: UInt8 = 0x3E      // >
    private static let slash: UInt8 = 0x2F   // /
    private static let amp: UInt8 = 0x26     // &
    private static let bang: UInt8 = 0x21    // !
    private static let dash: UInt8 = 0x2D    // -
    private static let equals: UInt8 = 0x3D  // =
    private static let dquote: UInt8 = 0x22
    private static let squote: UInt8 = 0x27
    private static let space: UInt8 = 0x20

    static func scan(_ s: UnsafeBufferPointer<UInt8>) -> [String] {
        var leaves: [Leaf] = []
        return scan(s, record: false, leaves: &leaves)
    }

    static func scanLeaves(_ s: UnsafeBufferPointer<UInt8>) -> [Leaf] {
        var leaves: [Leaf] = []
        _ = scan(s, record: true, leaves: &leaves)
        return leaves
    }

    private static func scan(_ s: UnsafeBufferPointer<UInt8>, record: Bool, leaves: inout [Leaf]) -> [String] {
        let n = s.count
        var out: [String] = []
        var src: [Int] = []
        var stack: [Frame] = []
        stack.reserveCapacity(16)
        var text: [UInt8] = []
        text.reserveCapacity(4096)
        var i = 0

        while i < n {
            let c = s[i]

            // Text
            if c != lt {
                if stack.isEmpty {
                    i += 1
                    while i < n, s[i] != lt { i += 1 }
                    continue
                }
                let before = text.count
                let at = i
                if c == amp {
                    i = decodeEntity(s, at: i, into: &text)
                } else if c == 0xC2, i + 1 < n, s[i + 1] == 0xA0 {
                    text.append(space) // NBSP reads as a space (JS does the same)
                    i += 2
                } else {
                    text.append(c)
                    i += 1
                }
                if record { for _ in before..<text.count { src.append(at) } }
                continue
            }

            // Markup
            let j = i + 1
            guard j < n else { break }

            if s[j] == bang {
                if j + 2 < n, s[j + 1] == dash, s[j + 2] == dash {
                    i = find(s, "-->", from: j + 3).map { $0 + 3 } ?? n
                } else {
                    i = index(of: gt, in: s, from: j).map { $0 + 1 } ?? n
                }
                continue
            }

            let isClose = s[j] == slash
            let nameStart = isClose ? j + 1 : j
            var nameEnd = nameStart
            while nameEnd < n, isAlnum(s[nameEnd]) { nameEnd += 1 }

            // A bare "<" that is not a tag: keep it as text.
            if nameEnd == nameStart {
                if !stack.isEmpty { text.append(c); if record { src.append(i) } }
                i += 1
                continue
            }

            let tagEnd = endOfTag(s, from: nameEnd)
            let after = min(tagEnd + 1, n)
            let id = tagID(s, nameStart, nameEnd)

            if isClose {
                if isListen(id), let k = stack.lastIndex(where: { $0.tag == id }) {
                    let frame = stack[k]
                    if !frame.hasBlockChild {
                        let emitted = emit(text, from: frame.textStart, into: &out)
                        if record, let (lo, str) = emitted {
                            leaves.append(Leaf(tagName: tagNames[frame.tag] ?? "p", text: str,
                                               openStart: frame.openStart, openEnd: frame.openEnd,
                                               source: Array(src[lo..<(lo + str.utf8.count)])))
                        }
                    }
                    stack.removeSubrange(k...)
                    if stack.isEmpty { text.removeAll(keepingCapacity: true); src.removeAll(keepingCapacity: true) }
                }
                i = after
                continue
            }

            switch id {
            case 1...15:
                let selfClosing = tagEnd < n && tagEnd > nameEnd && s[tagEnd - 1] == slash
                if !selfClosing {
                    if !stack.isEmpty { stack[stack.count - 1].hasBlockChild = true }
                    stack.append(Frame(tag: id, hasBlockChild: false, textStart: text.count,
                                       openStart: i, openEnd: after))
                }
                i = after
            case br:
                if !stack.isEmpty { text.append(space); if record { src.append(i) } }
                i = after
            case script, style:
                i = skipRawText(s, from: after, name: id == script ? "script" : "style")
            default:
                i = after
            }
        }
        return out
    }

    // MARK: Helpers

    /// Returns (byte offset of the emitted text in `text`, emitted string) when something was emitted.
    @discardableResult
    private static func emit(_ text: [UInt8], from start: Int, into out: inout [String]) -> (Int, String)? {
        var lo = start
        var hi = text.count
        while lo < hi, isSpace(text[lo]) { lo += 1 }
        while hi > lo, isSpace(text[hi - 1]) { hi -= 1 }
        guard lo < hi else { return nil }
        let str = text.withUnsafeBufferPointer {
            String(decoding: UnsafeBufferPointer(rebasing: $0[lo..<hi]), as: UTF8.self)
        }
        // Catch Unicode spaces the ASCII trim skipped.
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        out.append(trimmed)
        let lead = str.range(of: trimmed).map { str.utf8.distance(from: str.startIndex, to: $0.lowerBound) } ?? 0
        return (lo + lead, trimmed)
    }

    // MARK: Splitting helpers

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]

    /// Inline elements open at `end` inside a block whose content starts at `start`:
    /// (lowercased name, raw opening tag bytes), outermost first.
    static func inlineStack(_ s: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> [(name: String, raw: [UInt8])] {
        var stack: [(name: String, raw: [UInt8])] = []
        var i = start
        while i < end {
            guard s[i] == lt, i + 1 < end else { i += 1; continue }
            let j = i + 1
            if s[j] == bang {
                if j + 2 < s.count, s[j + 1] == dash, s[j + 2] == dash {
                    i = find(s, "-->", from: j + 3).map { $0 + 3 } ?? s.count
                } else {
                    i = index(of: gt, in: s, from: j).map { $0 + 1 } ?? s.count
                }
                continue
            }
            let isClose = s[j] == slash
            let nameStart = isClose ? j + 1 : j
            var nameEnd = nameStart
            while nameEnd < s.count, isAlnum(s[nameEnd]) { nameEnd += 1 }
            guard nameEnd > nameStart else { i += 1; continue }
            let name = String(decoding: UnsafeBufferPointer(rebasing: s[nameStart..<nameEnd]), as: UTF8.self).lowercased()
            let tagEnd = endOfTag(s, from: nameEnd)
            let after = min(tagEnd + 1, s.count)
            if isClose {
                if let k = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(k...) }
            } else {
                let selfClosing = tagEnd < s.count && tagEnd > nameEnd && s[tagEnd - 1] == slash
                if !selfClosing, !voidTags.contains(name) {
                    stack.append((name, Array(UnsafeBufferPointer(rebasing: s[i..<after]))))
                }
            }
            i = after
        }
        return stack
    }

    /// The block's opening tag with any `id` attribute removed (ids must stay unique).
    static func openTagWithoutID(_ s: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> [UInt8] {
        let raw = String(decoding: UnsafeBufferPointer(rebasing: s[start..<end]), as: UTF8.self)
        let cleaned = raw.replacingOccurrences(
            of: #"(?i)\s+id\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        return Array(cleaned.utf8)
    }

    @inline(__always) private static func isListen(_ id: UInt8) -> Bool {
        id >= 1 && id <= 15
    }

    @inline(__always) private static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x0A || b == 0x09 || b == 0x0D || b == 0x0C
    }

    @inline(__always) private static func isAlnum(_ b: UInt8) -> Bool {
        (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39)
    }

    @inline(__always) private static func lower(_ b: UInt8) -> UInt8 {
        (b >= 0x41 && b <= 0x5A) ? b | 0x20 : b
    }

    private static func tagID(_ s: UnsafeBufferPointer<UInt8>, _ a: Int, _ b: Int) -> UInt8 {
        switch b - a {
        case 1:
            return lower(s[a]) == 0x70 ? 7 : none // p
        case 2:
            let c0 = lower(s[a]), c1 = lower(s[a + 1])
            if c0 == 0x68, c1 >= 0x31, c1 <= 0x36 { return c1 - 0x30 } // h1-h6
            if c0 == 0x6C, c1 == 0x69 { return 8 }                     // li
            if c0 == 0x62, c1 == 0x72 { return br }                    // br
            if c0 == 0x74, c1 == 0x64 { return 11 }                    // td
            if c0 == 0x74, c1 == 0x68 { return 12 }                    // th
            if c0 == 0x64, c1 == 0x74 { return 13 }                    // dt
            if c0 == 0x64, c1 == 0x64 { return 14 }                    // dd
            return none
        case 3:
            return equalsCI(s, a, "pre") ? 10 : none
        case 5:
            return equalsCI(s, a, "style") ? style : none
        case 6:
            return equalsCI(s, a, "script") ? script : none
        case 10:
            if equalsCI(s, a, "blockquote") { return 9 }
            return equalsCI(s, a, "figcaption") ? 15 : none
        default:
            return none
        }
    }

    private static func equalsCI(_ s: UnsafeBufferPointer<UInt8>, _ a: Int, _ word: StaticString) -> Bool {
        let w = UnsafeBufferPointer(start: word.utf8Start, count: word.utf8CodeUnitCount)
        guard a + w.count <= s.count else { return false }
        for k in 0..<w.count where lower(s[a + k]) != w[k] { return false }
        return true
    }

    /// Index of the `>` that ends a tag, skipping quoted attribute values. `n` if unterminated.
    private static func endOfTag(_ s: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        let n = s.count
        var k = start
        while k < n {
            let ch = s[k]
            if ch == gt { return k }
            if ch == equals {
                k += 1
                while k < n, isSpace(s[k]) { k += 1 }
                if k < n, s[k] == dquote || s[k] == squote {
                    let q = s[k]
                    k += 1
                    while k < n, s[k] != q { k += 1 }
                    k += 1
                }
                continue
            }
            k += 1
        }
        return n
    }

    private static func index(of byte: UInt8, in s: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        var k = start
        while k < s.count {
            if s[k] == byte { return k }
            k += 1
        }
        return nil
    }

    private static func find(_ s: UnsafeBufferPointer<UInt8>, _ needle: StaticString, from start: Int) -> Int? {
        let w = UnsafeBufferPointer(start: needle.utf8Start, count: needle.utf8CodeUnitCount)
        guard let first = w.first else { return nil }
        var k = start
        while k + w.count <= s.count {
            if s[k] == first {
                var ok = true
                for m in 1..<w.count where s[k + m] != w[m] { ok = false; break }
                if ok { return k }
            }
            k += 1
        }
        return nil
    }

    /// Skip `<script>` / `<style>` contents up to and past the matching close tag.
    private static func skipRawText(_ s: UnsafeBufferPointer<UInt8>, from start: Int, name: StaticString) -> Int {
        let n = s.count
        let len = name.utf8CodeUnitCount
        var k = start
        while k + 1 < n {
            if s[k] == lt, s[k + 1] == slash, equalsCI(s, k + 2, name),
               k + 2 + len <= n, k + 2 + len == n || !isAlnum(s[k + 2 + len]) {
                let end = endOfTag(s, from: k + 2 + len)
                return min(end + 1, n)
            }
            k += 1
        }
        return n
    }

    // MARK: Entities

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ",
        "shy": "", "zwj": "", "zwnj": "",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "lsaquo": "\u{2039}", "rsaquo": "\u{203A}",
        "bull": "\u{2022}", "middot": "\u{00B7}", "prime": "\u{2032}", "Prime": "\u{2033}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}",
        "deg": "\u{00B0}", "times": "\u{00D7}", "divide": "\u{00F7}",
        "plusmn": "\u{00B1}", "frac12": "\u{00BD}", "frac14": "\u{00BC}", "frac34": "\u{00BE}",
        "euro": "\u{20AC}", "pound": "\u{00A3}", "yen": "\u{00A5}", "cent": "\u{00A2}",
        "sect": "\u{00A7}", "para": "\u{00B6}", "dagger": "\u{2020}", "Dagger": "\u{2021}",
    ]

    /// Decode `&...;` at `i` into `text`. Unknown or malformed entities stay literal.
    private static func decodeEntity(_ s: UnsafeBufferPointer<UInt8>, at i: Int, into text: inout [UInt8]) -> Int {
        let n = s.count
        var k = i + 1
        let limit = min(n, i + 34)
        while k < limit, s[k] != 0x3B /* ; */, s[k] != amp, s[k] != lt, !isSpace(s[k]) { k += 1 }
        guard k < limit, s[k] == 0x3B, k > i + 1 else {
            text.append(amp)
            return i + 1
        }
        let body = UnsafeBufferPointer(rebasing: s[(i + 1)..<k])

        if body[0] == 0x23 /* # */ {
            var value: UInt32 = 0
            var digits = 0
            let hex = body.count > 1 && (body[1] == 0x78 || body[1] == 0x58)
            for b in body.dropFirst(hex ? 2 : 1) {
                let d: UInt32
                switch b {
                case 0x30...0x39: d = UInt32(b - 0x30)
                case 0x61...0x66 where hex: d = UInt32(b - 0x61 + 10)
                case 0x41...0x46 where hex: d = UInt32(b - 0x41 + 10)
                default: text.append(amp); return i + 1
                }
                value = value &* (hex ? 16 : 10) &+ d
                digits += 1
                if value > 0x10FFFF { break }
            }
            guard digits > 0, let scalar = Unicode.Scalar(value) else {
                text.append(amp)
                return i + 1
            }
            if value == 0xA0 {
                text.append(space)
            } else {
                UTF8.encode(scalar) { text.append($0) }
            }
            return k + 1
        }

        let name = String(decoding: body, as: UTF8.self)
        guard let replacement = named[name] else {
            text.append(amp)
            return i + 1
        }
        text.append(contentsOf: replacement.utf8)
        return k + 1
    }
}
