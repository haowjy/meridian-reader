import Foundation

/// Limits for cutting a book into chapters. A fixed "top level of the contents" rule fails on
/// real books (chapters nested under one entry; a contents with one entry); these bounds were
/// checked against books from Gutenberg, Standard Ebooks and the Internet Archive.
///
/// Word counts here are provisional: they're counted on the raw XHTML (`EPUBWordCount`), before
/// the normalizer turns a chapter into listen blocks. Part 2 finalizes cuts, emptiness and sizes
/// against the listen blocks.
struct EPUBCutRules: Equatable, Sendable {
    /// No piece longer than this: a longer range is cut deeper in the contents, then at its
    /// `h1`/`h2` headings, then packed at file boundaries, between blocks, between the sentences
    /// (or words) of a paragraph too long to keep whole, and last at any text.
    var maxWords = 30_000
    /// A range shorter than this merges into a neighbour of the same kind (body, or skipped)
    /// that can take it without passing `maxWords`. Packing leaves no piece shorter than this
    /// where the cut points allow.
    var mergeBelowWords = 150
    /// A range no contents entry names, shorter than this, is skipped in playback (a cover page).
    var unlistedSkipBelowWords = 40

    /// Text longer than this is cut into runs (`EPUBTextRuns`): the cut points inside one
    /// paragraph, so a paragraph over `maxWords` can still be split under it.
    var maxRunWords: Int { max(1, maxWords / 10) }

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
    /// Words in the raw XHTML (`EPUBWordCount`); part 2 recounts on the listen blocks.
    var provisionalWordCount: Int
    var skipsInPlayback: Bool
}

/// Cuts the stream into chapters at the contents' anchors, choosing the depth per branch:
/// - cut at the top level of the contents;
/// - a range over `maxWords` whose entry has children is replaced by its children, recursively;
/// - a range still over it is split at `h1`, then `h2` headings, then packed (`packed`) so no
///   piece is over it;
/// - a range with no words merges into the next; one under `mergeBelowWords` merges into the
///   next range of the same kind (body or skipped), else the previous one, if that stays within
///   `maxWords`; so does a skipped range no entry names, whatever its length.
///
/// Without usable contents, chapters start at `h1` headings, else `h2`, else at each file.
/// The top of the book, Gutenberg's header and licence, and non-linear files (the nav among them)
/// are always cut points: text before the first entry is a chapter of its own, and the others are
/// skipped as whole chapters, never read inside another.
///
/// **The bar, provisionally:** no chapter over `maxWords`, always. A body chapter under 100
/// words remains only where it can't merge: no neighbouring body chapter can take it without
/// passing `maxWords` (its neighbours are full, or it has none, as in a whole book under 100
/// words or a short section between skipped matter).
struct EPUBChapterCutter {
    typealias Position = EPUBTextStream.Position

    let stream: EPUBTextStream
    let rules: EPUBCutRules

    private enum Origin {
        /// A contents entry.
        case contents
        /// A heading or file, for a book without usable contents.
        case derived
        /// A heading, file, block or run inside a range that was too long.
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

    /// Cut points for packing a too-long range, coarsest first; each includes the ones before.
    private enum PackingLevel: CaseIterable {
        case files, blocks, runs, text
    }

    private struct Candidate {
        var position: Position
        /// Words from the start of the range.
        var offset: Int
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
            var edges = document.boilerplate.flatMap { [$0.lowerBound, $0.upperBound] }
            if !document.linear { edges += [0, document.events.count] }
            for event in edges {
                let position = stream.normalized(Position(document: documentIndex, event: event))
                if position < stream.end { marks.append(unlistedMark(at: position)) }
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
                    locator: range.locator, provisionalWordCount: range.words, skipsInPlayback: range.skips)
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
        for level in 1...2 {
            pieces = pieces.flatMap { piece in
                cutting(piece) { start, end in
                    headingStarts(level: level, from: start, to: end).map {
                        mark(at: $0, title: headingText(at: $0), origin: .split)
                    }
                }
            }
        }
        return pieces.flatMap { piece in
            cutting(piece) { start, end in
                packed(from: start, to: end).map { mark(at: $0, title: nil, origin: .split) }
            }
        }
    }

    /// The piece unchanged when it's within `maxWords`, else cut at the marks `cuts` gives.
    private func cutting(_ piece: (mark: Mark, end: Position),
                         at cuts: (Position, Position) -> [Mark]) -> [(mark: Mark, end: Position)] {
        guard stream.words(from: piece.mark.position, to: piece.end) > rules.maxWords else { return [piece] }
        let marks = [piece.mark] + cuts(piece.mark.position, piece.end)
        return marks.indices.map { (marks[$0], $0 + 1 < marks.count ? marks[$0 + 1].position : piece.end) }
    }

    /// Headings of a level in the range, never one with no words before it.
    private func headingStarts(level: Int, from start: Position, to end: Position) -> [Position] {
        var points: [Position] = []
        var previous = start
        for candidate in stream.elementStarts(from: start, to: end, where: { $0.localName == "h\(level)" })
        where candidate > previous && stream.words(from: previous, to: candidate) > 0 {
            points.append(candidate)
            previous = candidate
        }
        return points
    }

    /// Cut points that make pieces of about equal size: none over `maxWords`, and none under
    /// `mergeBelowWords` where the cut points allow. Each cut is the one closest to an even split
    /// of what's left, taken from the coarsest level that has one: file boundaries (so a book of
    /// one file per page is gathered into chapters, not one each), then between blocks, between
    /// the runs of a long paragraph, then at any text. Runs are at most `maxRunWords`, so the last
    /// level always has a cut within `maxWords`.
    private func packed(from start: Position, to end: Position) -> [Position] {
        let total = stream.words(from: start, to: end)
        let target = max(1, rules.maxWords * 4 / 5)
        var levels: [PackingLevel: [Candidate]] = [:]
        func candidates(_ level: PackingLevel) -> [Candidate] {
            if let cached = levels[level] { return cached }
            let found = packingCandidates(level, from: start, to: end).map {
                Candidate(position: $0, offset: stream.words(from: start, to: $0))
            }
            levels[level] = found
            return found
        }
        var chosen: [Position] = []
        var pieceStart = 0
        while total - pieceStart > rules.maxWords {
            let remaining = total - pieceStart
            let pieceCount = (remaining + target - 1) / target
            let ideal = pieceStart + remaining / pieceCount
            var cut: Candidate?
            for level in PackingLevel.allCases {
                cut = closest(in: candidates(level), to: ideal, after: pieceStart, total: total,
                              minimum: rules.mergeBelowWords)
                if cut != nil { break }
            }
            if cut == nil {
                cut = closest(in: candidates(.text), to: ideal, after: pieceStart, total: total, minimum: 1)
            }
            guard let cut else { break }
            chosen.append(cut.position)
            pieceStart = cut.offset
        }
        return chosen
    }

    /// The candidate closest to `ideal` leaving `minimum`…`maxWords` words since `pieceStart` and
    /// at least `minimum` after it; the earlier of two equally close. `candidates` are sorted.
    private func closest(in candidates: [Candidate], to ideal: Int, after pieceStart: Int, total: Int,
                         minimum: Int) -> Candidate? {
        let low = pieceStart + minimum
        let high = min(pieceStart + rules.maxWords, total - minimum)
        guard low <= high else { return nil }
        var lower = 0
        var upper = candidates.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if candidates[middle].offset < low { lower = middle + 1 } else { upper = middle }
        }
        var best: Candidate?
        for candidate in candidates[lower...] {
            guard candidate.offset <= high else { break }
            if best.map({ abs(candidate.offset - ideal) < abs($0.offset - ideal) }) ?? true { best = candidate }
        }
        return best
    }

    private func packingCandidates(_ level: PackingLevel, from start: Position, to end: Position) -> [Position] {
        var positions = (start.document + 1..<stream.documents.count)
            .map { stream.normalized(Position(document: $0, event: 0)) }
        if level != .files {
            positions += stream.elementStarts(from: start, to: end) { Self.blockElements.contains($0.localName) }
        }
        if level == .runs || level == .text {
            positions += stream.runStarts(from: start, to: end)
        }
        if level == .text {
            positions += stream.textStarts(from: start, to: end)
        }
        return Set(positions).filter { $0 > start && $0 < end }.sorted()
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

    /// See the type's comment for the one case a short body range stays.
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
            // Skipped matter no entry names (the start of Gutenberg's licence) joins skipped
            // matter beside it at any length, rather than listing as an untitled chapter.
            let mergesAnyLength = range.skips && range.origin == .unlisted
            if range.words < rules.mergeBelowWords || mergesAnyLength, let into = [index + 1, index - 1].first(where: {
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
