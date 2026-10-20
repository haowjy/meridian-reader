import Foundation

/// A book chapter as an import keeps it: the cut's identity (key, place, skip flag), its title,
/// and its normalized HTML with the listen blocks built from that HTML and title, as the library
/// and the reader build them (`ParagraphDocument.forListening`), so reader indices equal speech
/// indices.
struct PreparedChapter: Equatable, Sendable {
    var key: UUID
    /// Its contents entry or heading; nil when the book names it neither way (`ArticleRowTitle`).
    var title: String?
    var locator: EPUBLocator
    var skipsInPlayback: Bool
    var html: String
    private(set) var document: ParagraphDocument
    /// `WordCount` of the listen blocks.
    private(set) var words: Int

    init(key: UUID, title: String?, locator: EPUBLocator, skipsInPlayback: Bool, html: String) {
        self.key = key
        self.locator = locator
        self.skipsInPlayback = skipsInPlayback
        self.html = html
        self.title = title.flatMap { $0.isEmpty ? nil : $0 }
        document = .empty
        words = 0
        rebuild()
    }

    init(_ chapter: EPUBChapter, normalizedHTML: String) {
        self.init(key: chapter.key, title: chapter.title, locator: chapter.locator,
                  skipsInPlayback: chapter.skipsInPlayback, html: normalizedHTML)
    }

    /// `other`, the chapter just before or after this one, joins it; this chapter keeps its key,
    /// title, place and skip flag.
    mutating func absorb(_ other: PreparedChapter, before: Bool) {
        html = before ? other.html + "\n" + html : html + "\n" + other.html
        rebuild()
    }

    private mutating func rebuild() {
        document = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title)
        words = WordCount.count(document.joinedText)
    }
}

/// Settles a book's chapters on their listen blocks, the text that is read and spoken, before any
/// key is kept. The cut was made on the raw XHTML, whose word counts are provisional; the
/// normalizer drops footnotes and anything that isn't text.
/// - A chapter with no listen blocks is dropped (a cover picture, an emptied footnote page).
/// - A book with no body chapter left plays every chapter: they are all body chapters from here.
/// - A body chapter under the bar's minimum joins the body chapter right after it, else the one
///   right before it, if the two stay within the maximum; otherwise it stays. Skipped chapters
///   (front and back matter) are kept whatever their length.
///
/// A body chapter over the maximum isn't settled here: the import cuts the book again with a
/// lower cap (`BookImporter`). `check` is the size policy the result is held to.
enum BookChapterFinalizer {
    /// The pass bar for a body chapter, in words.
    struct Bar: Equatable, Sendable {
        var minWords = 100
        var maxWords = EPUBCutRules.standard.maxWords

        static let standard = Bar()
    }

    static func finalize(_ chapters: [PreparedChapter], bar: Bar = .standard) -> [PreparedChapter] {
        let minWords = bar.minWords, maxWords = bar.maxWords
        var out = chapters.filter { !$0.document.isEmpty }
        if !out.contains(where: { !$0.skipsInPlayback }) {
            for j in out.indices { out[j].skipsInPlayback = false }
        }
        var i = 0
        while i < out.count {
            let short = out[i]
            guard !short.skipsInPlayback, short.words < minWords else {
                i += 1
                continue
            }
            if i + 1 < out.count, !out[i + 1].skipsInPlayback, short.words + out[i + 1].words <= maxWords {
                out[i + 1].absorb(short, before: true)
                out.remove(at: i)
            } else if i > 0, !out[i - 1].skipsInPlayback, out[i - 1].words + short.words <= maxWords {
                out[i - 1].absorb(short, before: false)
                out.remove(at: i)
                i -= 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// The longest body chapter's words, when it is over the bar.
    static func overCap(_ chapters: [PreparedChapter], bar: Bar = .standard) -> Int? {
        let longest = chapters.filter { !$0.skipsInPlayback }.map(\.words).max() ?? 0
        return longest > bar.maxWords ? longest : nil
    }

    /// A chapter as the size policy sees it: whether it has listen blocks, and their words.
    struct Measure: Equatable {
        var title: String?
        var hasBlocks: Bool
        var words: Int
        var skipsInPlayback: Bool

        init(title: String?, hasBlocks: Bool = true, words: Int, skipsInPlayback: Bool = false) {
            self.title = title
            self.hasBlocks = hasBlocks
            self.words = words
            self.skipsInPlayback = skipsInPlayback
        }

        /// What the library will store for the chapter: its listen blocks.
        init(_ chapter: ArticleContent) {
            self.init(title: chapter.title, hasBlocks: !chapter.document.isEmpty,
                      words: WordCount.count(chapter.document.joinedText), skipsInPlayback: chapter.ref.skipsInPlayback)
        }
    }

    /// Why settled chapters can't be stored.
    enum Rejection: Equatable {
        /// Nothing left to read: every chapter normalized to no listen blocks.
        case noText
        /// A chapter with no listen blocks.
        case emptyChapter(title: String?)
        /// A body chapter over the maximum: cutting again didn't bring it under.
        case overBar(title: String?, words: Int)
        /// A body chapter under the minimum that a neighbouring body chapter could have taken.
        case short(title: String?, words: Int)
    }

    /// The size policy, held on the listen blocks the library will store, before it stores any:
    /// at least one chapter, each with something to read; no body chapter over the maximum; and
    /// none under the minimum, except where no neighbouring body chapter can take it without
    /// passing the maximum (the cutter's stated exception): its body neighbours are full, or it
    /// has none, as in a book under 100 words, or a short section between skipped matter.
    /// Skipped chapters may be any length. nil when the chapters pass.
    static func check(_ chapters: [Measure], bar: Bar = .standard) -> Rejection? {
        guard !chapters.isEmpty else { return .noText }
        if let empty = chapters.first(where: { !$0.hasBlocks }) { return .emptyChapter(title: empty.title) }
        for (i, chapter) in chapters.enumerated() where !chapter.skipsInPlayback {
            if chapter.words > bar.maxWords { return .overBar(title: chapter.title, words: chapter.words) }
            guard chapter.words < bar.minWords else { continue }
            let canTake = [i - 1, i + 1].contains { j in
                chapters.indices.contains(j) && !chapters[j].skipsInPlayback
                    && chapters[j].words + chapter.words <= bar.maxWords
            }
            if canTake { return .short(title: chapter.title, words: chapter.words) }
        }
        return nil
    }
}
