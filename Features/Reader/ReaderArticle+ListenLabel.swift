import Foundation

extension ReaderArticle {
    /// Listen's title and the lighter time after it, at `rate`: "Listen" "9 min", "Continue"
    /// "6 min left", "Listen Again" (no time).
    func listenLabel(from start: ListenSpot, finished: Bool, rate: Double) -> (title: String, detail: String?) {
        if finished { return (String(localized: "Listen Again"), nil) }
        if start.isPartWay, document.paragraphs.indices.contains(start.paragraph) {
            let at = start.resolved(in: document).utf16Offset
            let left = ListeningTime.minutesLeft(in: document, fromUTF16Offset: at, rate: rate)
            return (Verbs.continue, ListeningTime.leftLabel(minutes: left))
        }
        let length = document.isEmpty ? plainText.utf16.count : document.utf16Length
        return (Verbs.listen, ListeningTime.label(minutes: ListeningTime.minutes(utf16Length: length, rate: rate)))
    }
}
