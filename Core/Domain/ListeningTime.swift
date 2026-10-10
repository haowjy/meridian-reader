import Foundation

/// Listening-time estimates from text length: "9 min", "6 min left". Spoken English runs at about
/// 180 words a minute at 1×, and a word plus its space is about 6 UTF-16 units.
enum ListeningTime {
    static let wordsPerMinute = 180.0
    static let unitsPerWord = 6.0

    /// Minutes to hear `utf16Length` units of text at `rate` (at least 1 while any text is left).
    static func minutes(utf16Length: Int, rate: Double = 1) -> Int {
        guard utf16Length > 0 else { return 0 }
        let words = Double(utf16Length) / unitsPerWord
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

    /// A length as rows and headers show it: "9 min", "1 h", "6 h 10 min".
    static func label(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }

    /// Minutes left in `document` from document offset `offset`.
    static func minutesLeft(in document: ParagraphDocument, fromUTF16Offset offset: Int, rate: Double = 1) -> Int {
        minutes(utf16Length: max(0, document.utf16Length - offset), rate: rate)
    }
}
