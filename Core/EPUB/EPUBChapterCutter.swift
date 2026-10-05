import Foundation

/// Limits for cutting a book into chapters (`docs`: probed on six real books, see the design's
/// "Choosing chapter depth").
struct EPUBCutRules: Equatable, Sendable {
    /// No body chapter longer than this: a longer range is cut deeper in the contents, then at
    /// its `h1`/`h2` headings, then at file boundaries, then between blocks.
    var maxWords = 30_000
    /// A range shorter than this merges into a neighbour of the same kind (body, or skipped).
    var mergeBelowWords = 150
    /// A range no contents entry names, shorter than this, is skipped in playback (a cover page).
    var unlistedSkipBelowWords = 40

    static let standard = EPUBCutRules()
}

/// Where a chapter is in its book: the part of the chapter's key that comes from the book.
struct EPUBLocator: Hashable, Sendable {
    /// Package path of the spine file.
    var href: String
    /// The contents entry's fragment; for a cut no entry names, the element's id, or `@<event>`.
    var fragment: String?
}

/// A chapter cut from the stream, before its markup is written.
struct EPUBCut: Equatable, Sendable {
    var start: EPUBTextStream.Position
    var end: EPUBTextStream.Position
    var title: String?
    var locator: EPUBLocator
    var wordCount: Int
    var skipsInPlayback: Bool
}

/// Cuts the stream into chapters at the contents' anchors, choosing the depth per branch:
/// - cut at the top level of the contents;
/// - a range over `maxWords` whose entry has children is replaced by its children, recursively;
/// - a range still over it is split at `h1`, then `h2` headings, else at file boundaries, else
///   between blocks;
/// - a range with no words merges into the next; one under `mergeBelowWords` merges into the
///   next range of the same kind (body or skipped), else the previous one.
///
/// Without usable contents, chapters start at `h1` headings, else `h2`, else at each file.
/// The top of the book and Gutenberg's header and licence are always cut points, so text before
/// the first entry is a chapter of its own, and the boilerplate is skipped as whole chapters.
struct EPUBChapterCutter {
    typealias Position = EPUBTextStream.Position

    let stream: EPUBTextStream
    let rules: EPUBCutRules

    private enum Origin {
        /// A contents entry.
        case contents
        /// A heading or file, for a book without usable contents.
        case derived
        /// A heading, file or block inside a range that was too long.
        case split
        /// The top of the book, or a boilerplate edge: no contents entry names it.
        case unlisted
    }

    private struct Mark {
        var position: Position
        var title: String?
        var locator: EPUBLocator
        var origin: Origin
        /// Contents entries below this one, not cut at yet.
        var children: [EPUBContentsEntry] = []
    }

    private struct Range {
        var start: Position
        var end: Position
        var title: String?
        var locator: EPUBLocator
        var origin: Origin
        var words: Int
        var skips: Bool
    }

    private enum SplitPoints {
        case headings(level: Int)
        case files
        case blocks
    }

    private static let blockElements: Set<String> = [
        "p", "div", "section", "article", "blockquote", "pre", "ul", "ol", "li", "dl", "table",
        "figure", "aside", "header", "footer", "hr", "h1", "h2", "h3", "h4", "h5", "h6",
    ]

    func cut(contents: [EPUBContentsEntry]) -> [EPUBCut] {
        guard !stream.documents.isEmpty, stream.start < stream.end else { return [] }
        var marks = contents.compactMap(mark(for:))
        if marks.isEmpty { marks = headingOrFileMarks() }
        marks.append(unlistedMark(at: stream.start))
        for (documentIndex, document) in stream.documents.enumerated() {
            for span in document.boilerplate {
                for event in [span.lowerBound, span.upperBound] {
                    let position = stream.normalized(Position(document: documentIndex, event: event))
                    if position < stream.end { marks.append(unlistedMark(at: position)) }
                }
            }
        }
        marks = expandingLongBranches(deduplicated(marks))
        var ranges: [Range] = []
        for index in marks.indices {
            let end = index + 1 < marks.count ? marks[index + 1].position : stream.end
            ranges += split(marks[index], end: end).map(classified)
        }
        var cuts = mergingShortRanges(ranges).map { range in
            EPUBCut(start: range.start, end: range.end,
                    title: range.title ?? firstHeading(from: range.start, to: range.end),
                    locator: range.locator, wordCount: range.words, skipsInPlayback: range.skips)
        }
        var seen = Set<EPUBLocator>()
        for index in cuts.indices {
            if seen.contains(cuts[index].locator) {
                let start = cuts[index].start
                cuts[index].locator.fragment = (cuts[index].locator.fragment ?? "") + "@\(start.document).\(start.event)"
            }
            seen.insert(cuts[index].locator)
        }
        return cuts
    }

    // MARK: - Marks

    private func mark(for entry: EPUBContentsEntry) -> Mark? {
        let title = entry.title.isEmpty ? nil : entry.title
        if let path = entry.path, let document = stream.documentIndex(ofPath: path),
           let position = stream.position(ofPath: path, fragment: entry.fragment) {
            let locator = EPUBLocator(href: stream.documents[document].path, fragment: entry.fragment)
            return Mark(position: position, title: title, locator: locator, origin: .contents, children: entry.children)
        }
        // A heading that links nowhere (or outside the spine) starts where its first child does.
        guard let first = entry.children.compactMap(mark(for:)).min(by: { $0.position < $1.position }) else {
            return nil
        }
        return Mark(position: first.position, title: title ?? first.title, locator: first.locator,
                    origin: .contents, children: entry.children)
    }

    private func headingOrFileMarks() -> [Mark] {
        for level in 1...2 {
            let starts = stream.elementStarts(from: stream.start, to: stream.end) { $0.localName == "h\(level)" }
            if !starts.isEmpty {
                return starts.map { mark(at: $0, title: headingText(at: $0), origin: .derived) }
            }
        }
        return stream.documents.indices.map {
            mark(at: stream.normalized(Position(document: $0, event: 0)), title: nil, origin: .derived)
        }
    }

    private func unlistedMark(at position: Position) -> Mark {
        mark(at: position, title: nil, origin: .unlisted)
    }

    private func mark(at position: Position, title: String?, origin: Origin) -> Mark {
        let locator = EPUBLocator(href: stream.documents[position.document].path,
                                  fragment: stream.fragment(at: position))
        return Mark(position: position, title: title, locator: locator, origin: origin)
    }

    /// Sorted by position, one mark per position: a named mark wins over an unlisted one, and of
    /// two named ones the later (the deeper entry, or the later in the contents) wins, keeping
    /// both one's children.
    private func deduplicated(_ marks: [Mark]) -> [Mark] {
        let sorted = marks.enumerated().sorted {
            $0.element.position == $1.element.position ? $0.offset < $1.offset : $0.element.position < $1.element.position
        }.map(\.element)
        var result: [Mark] = []
        for mark in sorted {
            guard let last = result.last, last.position == mark.position else {
                result.append(mark)
                continue
            }
            if mark.origin == .unlisted { continue }
            if last.origin == .unlisted {
                result[result.count - 1] = mark
                continue
            }
            var kept = mark
            kept.children = last.children + mark.children
            result[result.count - 1] = kept
        }
        return result
    }

    /// Replaces a too-long range whose entry has children with the entry's own start plus its
    /// children, until no such range is left.
    private func expandingLongBranches(_ marks: [Mark]) -> [Mark] {
        var marks = marks
        var expanded = true
        while expanded {
            expanded = false
            for index in marks.indices where !marks[index].children.isEmpty {
                let end = index + 1 < marks.count ? marks[index + 1].position : stream.end
                guard stream.words(from: marks[index].position, to: end) > rules.maxWords else { continue }
                let children = marks[index].children.compactMap(mark(for:))
                marks[index].children = []
                marks = deduplicated(marks + children)
                expanded = true
                break
            }
        }
        return marks
    }

    // MARK: - Splitting long ranges

    private func split(_ first: Mark, end: Position) -> [(mark: Mark, end: Position)] {
        var pieces = [(mark: first, end: end)]
        for strategy in [SplitPoints.headings(level: 1), .headings(level: 2), .files, .blocks] {
            var next: [(mark: Mark, end: Position)] = []
            for piece in pieces {
                guard stream.words(from: piece.mark.position, to: piece.end) > rules.maxWords else {
                    next.append(piece)
                    continue
                }
                let marks = [piece.mark] + splitPoints(strategy, from: piece.mark.position, to: piece.end).map {
                    if case .headings = strategy {
                        return mark(at: $0, title: headingText(at: $0), origin: .split)
                    }
                    return mark(at: $0, title: nil, origin: .split)
                }
                for index in marks.indices {
                    next.append((marks[index], index + 1 < marks.count ? marks[index + 1].position : piece.end))
                }
            }
            pieces = next
        }
        return pieces
    }

    private func splitPoints(_ strategy: SplitPoints, from start: Position, to end: Position) -> [Position] {
        let candidates: [Position]
        switch strategy {
        case .headings(let level):
            candidates = stream.elementStarts(from: start, to: end) { $0.localName == "h\(level)" }
        case .files:
            candidates = (start.document + 1..<stream.documents.count)
                .map { stream.normalized(Position(document: $0, event: 0)) }
                .filter { $0 < end }
        case .blocks:
            candidates = stream.elementStarts(from: start, to: end) { Self.blockElements.contains($0.localName) }
        }
        // Never a cut with no words before it.
        var points: [Position] = []
        var previous = start
        for candidate in candidates where candidate > previous && candidate < end {
            guard stream.words(from: previous, to: candidate) > 0 else { continue }
            points.append(candidate)
            previous = candidate
        }
        if case .headings = strategy { return points }
        return packed(points, from: start, to: end)
    }

    /// Of the possible cut points, the ones that make pieces of about equal size, each well under
    /// the cap: pages of a book that has one file per page are gathered up, not each a chapter.
    private func packed(_ points: [Position], from start: Position, to end: Position) -> [Position] {
        let total = stream.words(from: start, to: end)
        let target = max(1, rules.maxWords * 4 / 5)
        let pieceCount = max(1, (total + target - 1) / target)
        let size = total / pieceCount
        var chosen: [Position] = []
        var pieceStart = start
        for point in points where stream.words(from: pieceStart, to: point) >= size {
            guard stream.words(from: point, to: end) > 0 else { break }
            chosen.append(point)
            pieceStart = point
        }
        return chosen
    }

    // MARK: - Classifying and merging

    private func classified(_ piece: (mark: Mark, end: Position)) -> Range {
        let start = piece.mark.position
        let words = stream.words(from: start, to: piece.end)
        let bodyWords = stream.bodyWords(from: start, to: piece.end)
        let skips = bodyWords == 0 || (piece.mark.origin == .unlisted && words < rules.unlistedSkipBelowWords)
        return Range(start: start, end: piece.end, title: piece.mark.title, locator: piece.mark.locator,
                     origin: piece.mark.origin, words: words, skips: skips)
    }

    private func mergingShortRanges(_ ranges: [Range]) -> [Range] {
        var ranges = ranges
        var index = 0
        while index < ranges.count, ranges.count > 1 {
            let range = ranges[index]
            if range.words == 0 {
                let into = index + 1 < ranges.count ? index + 1 : index - 1
                ranges[into] = absorbing(range, into: ranges[into])
                ranges.remove(at: index)
                continue
            }
            if range.words < rules.mergeBelowWords, let into = [index + 1, index - 1].first(where: {
                ranges.indices.contains($0) && ranges[$0].skips == range.skips
                    && ranges[$0].words + range.words <= rules.maxWords
            }) {
                ranges[into] = absorbing(range, into: ranges[into])
                ranges.remove(at: index)
                continue
            }
            index += 1
        }
        return ranges
    }

    /// The absorbing range keeps its title (unless it has none), locator and kind.
    private func absorbing(_ range: Range, into primary: Range) -> Range {
        var merged = primary
        merged.start = min(primary.start, range.start)
        merged.end = max(primary.end, range.end)
        merged.words += range.words
        merged.title = primary.title ?? range.title
        return merged
    }

    // MARK: - Titles

    private func headingText(at position: Position) -> String? {
        let text = stream.documents[position.document].text(ofElementAt: position.event)
        return text.isEmpty ? nil : text
    }

    private func firstHeading(from start: Position, to end: Position) -> String? {
        let headings = stream.elementStarts(from: start, to: end) { EPUBSpineDocument.headingLevel($0.localName) != nil }
        return headings.lazy.compactMap(headingText(at:)).first
    }
}
