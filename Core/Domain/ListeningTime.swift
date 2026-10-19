import Foundation

/// Listening-time estimates, the one reading rate and the one way to show them: "9 min",
/// "6 h 10 min left". Spoken English runs at about 180 words a minute at 1×, and a word plus its
/// space is about 6 UTF-16 units.
///
/// Every estimate names its playback `rate`, and every surface passes the current speed
/// (`SpeechController.rateMultiplier`): rows, folder headers, the Reader's length and Listen,
/// the Now Playing bar and Now Playing all count at the speed you hear, lengths and time left
/// alike, so a length and the time left after it agree.
enum ListeningTime {
    static let wordsPerMinute = 180.0
    static let unitsPerWord = 6.0

    /// Minutes to hear `words` words at `rate` (at least 1 while any word is left).
    static func minutes(words: Int, rate: Double) -> Int {
        minutes(words: Double(words), rate: rate)
    }

    /// Minutes to hear `utf16Length` units of text at `rate` (at least 1 while any text is left).
    static func minutes(utf16Length: Int, rate: Double) -> Int {
        minutes(words: words(utf16Length: utf16Length), rate: rate)
    }

    /// The words in `utf16Length` units of listen text, on the one measure: a length that doesn't
    /// depend on the speed, for sums rounded to minutes once (a folder's time left and fraction).
    static func words(utf16Length: Int) -> Double {
        Double(utf16Length) / unitsPerWord
    }

    /// Minutes to hear `words` words (on the one measure, possibly a fraction) at `rate`.
    static func minutes(words: Double, rate: Double) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int((words / (wordsPerMinute * max(0.25, rate))).rounded(.up)))
    }

    /// Fewer words than this is nothing to listen to (a page whose article text is hidden, or a
    /// stub): about ten seconds of speech.
    static let minimumWords = 25

    /// At least `minimumWords` words (by the system's word boundaries), counted until there are
    /// enough.
    static func hasEnoughToListen(_ document: ParagraphDocument) -> Bool {
        var words = 0
        for paragraph in document.paragraphs {
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: [.byWords, .substringNotRequired]) {
                _, _, _, stop in
                words += 1
                if words >= minimumWords { stop = true }
            }
            if words >= minimumWords { return true }
        }
        return false
    }

    /// Minutes left in `document` from document offset `offset`, at `rate`.
    static func minutesLeft(in document: ParagraphDocument, fromUTF16Offset offset: Int, rate: Double) -> Int {
        minutes(utf16Length: max(0, document.utf16Length - offset), rate: rate)
    }

    /// A length: "9 min", "1 h", "6 h 10 min".
    static func label(minutes: Int) -> String {
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return String(localized: "\(minutes) min") }
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }

    /// What is left: "9 min left", "1 h left", "6 h 10 min left".
    static func leftLabel(minutes: Int) -> String {
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return String(localized: "\(minutes) min left") }
        return rest == 0 ? String(localized: "\(hours) h left") : String(localized: "\(hours) h \(rest) min left")
    }

    /// What is left of `document` from `offset` UTF-16 units into paragraph `paragraph`, at `rate`
    /// (Pages mode's footer, from a page's first character): "2 min left in chapter", "1 h 5 min
    /// left in chapter"; nil for an empty document.
    static func leftInChapterLabel(in document: ParagraphDocument, paragraph: Int, offset: Int,
                                   rate: Double) -> String? {
        guard !document.isEmpty else { return nil }
        let minutes = minutesLeft(in: document, fromUTF16Offset: document.startUTF16Offset(forParagraph: paragraph) + offset,
                                  rate: rate)
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return String(localized: "\(minutes) min left in chapter") }
        return rest == 0 ? String(localized: "\(hours) h left in chapter")
            : String(localized: "\(hours) h \(rest) min left in chapter")
    }

    /// "✓ Finished", where a time left would be.
    static var finishedLabel: String { String(localized: "✓ Finished") }
}
