import Foundation

/// A book chapter as an import keeps it: the cut's identity (key, place, skip flag), its title,
/// and its normalized HTML with the listen blocks built from that HTML and title, as the library
/// and the reader build them (`ParagraphDocument.forListening`), so reader indices equal speech
/// indices.
struct PreparedChapter: Equatable, Sendable {
    var key: UUID
    var title: String
    var locator: EPUBLocator
    var skipsInPlayback: Bool
    var html: String
    private(set) var document: ParagraphDocument
    /// `EPUBWordCount` of the listen blocks.
    private(set) var words: Int

    /// `title` nil: the chapter's first words (a chapter no contents entry names).
    init(key: UUID, title: String?, locator: EPUBLocator, skipsInPlayback: Bool, html: String) {
        self.key = key
        self.locator = locator
        self.skipsInPlayback = skipsInPlayback
        self.html = html
        self.title = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.firstWords(of: ParagraphDocument.forListening(plainText: "", cleanedHTML: html))
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
        words = EPUBWordCount.count(document.joinedText)
    }

    /// The first listen block, cut after `wordLimit` words.
    static func firstWords(of document: ParagraphDocument, wordLimit: Int = 8) -> String {
        guard let first = document.paragraphs.first else { return String(localized: "Untitled") }
        let words = first.split(whereSeparator: \.isWhitespace)
        return words.count <= wordLimit ? first : words.prefix(wordLimit).joined(separator: " ") + "…"
    }
}

/// Settles a book's chapters on their listen blocks, the text that is read and spoken, before any
/// key is kept. The cut was made on the raw XHTML, whose word counts are provisional; the
/// normalizer drops footnotes and anything that isn't text.
/// - A chapter with no listen blocks is dropped (a cover picture, an emptied footnote page).
/// - A body chapter under the bar's minimum joins the body chapter right after it, else the one
///   right before it, if the two stay within the maximum; otherwise it stays. Skipped chapters
///   (front and back matter) are kept whatever their length.
/// - A book with no body chapter left plays every chapter.
///
/// A body chapter over the maximum isn't settled here: the import cuts the book again with a
/// lower cap (`BookImporter`).
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
        if !out.contains(where: { !$0.skipsInPlayback }) {
            for j in out.indices { out[j].skipsInPlayback = false }
        }
        return out
    }

    /// The longest body chapter's words, when it is over the bar.
    static func overCap(_ chapters: [PreparedChapter], bar: Bar = .standard) -> Int? {
        let longest = chapters.filter { !$0.skipsInPlayback }.map(\.words).max() ?? 0
        return longest > bar.maxWords ? longest : nil
    }
}
