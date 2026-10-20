#if DEBUG
import Foundation

/// `-seedDemoBook` (Debug builds only): a short synthetic book, written for this app, to check
/// playback across chapter boundaries before the Library screens exist. A title page that
/// playback skips, three chapters of six paragraphs (about a minute and a half each with Kokoro at 1×),
/// and one page in no folder. The chapters are also offline test pages
/// (`reader-test://articles/book-N`), so a UI test can open one in the Reader from the browser.
enum DemoBook {
    struct Chapter {
        var title: String
        var paragraphs: [String]
        /// Front matter: never reached by carrying on.
        var skipsInPlayback = false

        var html: String { paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n") }
        var plainText: String { paragraphs.joined(separator: "\n\n") }
    }

    static let title = "Demo Folder"
    static let author = "Demo Author"
    /// Marks the seeded folder, so the next seed replaces it.
    static let sourceIdentifier = "debug.demo-book"

    static let chapters: [Chapter] = [
        Chapter(title: "Title Page", paragraphs: [
            "Demo Folder. A short folder written to test listening from one chapter to the next.",
        ], skipsInPlayback: true),
        Chapter(title: "Chapter 1: The Harbor", paragraphs: [
            "The harbor woke before the town did. Gulls circled the fishing boats while the first lamps came on along the quay, one window at a time, and the smell of coffee drifted down from the bakery on the corner.",
            "Mara carried two baskets down the stone steps. She had made the walk every morning for eleven years, and she still counted the steps under her breath, the way her grandmother had taught her when she was small.",
            "At the bottom, the harbor master was already arguing with the wind. He held his hat with one hand and a clipboard with the other, and he was losing on both counts, which seemed to make him argue all the harder.",
            "The boats rocked against their ropes like restless horses. Somewhere a radio played a song that nobody would admit to knowing the words of, and somebody on a deck was humming along to it anyway, slightly off key.",
            "Mara set the baskets down beside the ice house and looked out past the breakwater. The sea was grey and flat, the color of a spoon left out in the rain, and the horizon had quietly disappeared into the mist.",
            "That is how the day began, the day the lighthouse went dark. Nobody noticed at first, because nobody ever looks at a light that is always on, any more than they listen for a clock that has always been ticking.",
        ]),
        Chapter(title: "Chapter 2: The Lighthouse", paragraphs: [
            "The lighthouse stood on a rock a mile from shore, white and patient. Its keeper had retired years ago, and since then the light had looked after itself, turning every night without anyone needing to ask it.",
            "By noon the fishermen were talking about it in low voices. A light that fails in daylight is a small thing, they said to each other, until the evening comes and the boats are out and the fog rolls in.",
            "Mara borrowed her uncle's rowing boat and a tin of tools from his shed. Her uncle did not ask her why she wanted them, which was his way of saying that he already knew, and that he thought she was right.",
            "The crossing took the better part of an hour. The oars creaked, the water slapped at the bow, and the rock grew slowly larger in front of her until it filled the whole sky and she could hear the waves on it.",
            "Inside, the spiral stairs smelled of salt and old paint. At the very top she found the great lens dusty but whole, and lying beside it a single burned out fuse, blackened at one end like a used match.",
            "She replaced the fuse with one from the tin and flipped the switch. Nothing happened for a long moment, long enough for her to start doubting herself, and then the whole room filled with a warm and steady light.",
        ]),
        Chapter(title: "Chapter 3: The Tide", paragraphs: [
            "The tide had turned while she worked. When Mara came back down the stairs, the rowing boat was floating higher than she had left it, tugging at its line as if it were impatient to be going home again.",
            "She rowed back with the current behind her, which made the trip half as long as the crossing out. Behind her the beam swept across the water in slow and steady circles, the way it had for as long as she could remember.",
            "On the quay a small crowd had gathered to wait for her. Nobody cheered, because that is not what people do in a harbor town, but several of them nodded at once, and one of them helped her tie up the boat.",
            "The harbor master wrote something on his clipboard and underlined it twice. Later she learned that it said only the date and the word fixed, which from him was about as close to a speech as anyone ever got.",
            "That night the boats went out as usual, and came home again guided by a light that nobody noticed, because nobody ever looks at a light that is always on, until the one evening when it is not.",
            "And that is the end of the demo folder. If you heard this last line, playback carried on through every chapter of the folder and then stopped by itself at the end, which is exactly what it is supposed to do.",
        ]),
    ]

    /// The page in no folder: it plays to its end and stops.
    static let looseArticle = Chapter(title: "Demo Loose Page", paragraphs: [
        "This page is in no folder. When it ends, playback stops instead of carrying on to another page.",
        "It is here so a folder and a single page can be compared side by side.",
    ])
    static let looseArticleURL = URL(string: "https://example.com/demo-loose-page")!
    /// Marks the page in no folder as the seed's (`Article.locator`, which no other page in no folder
    /// has: it is a book chapter's place in its book), so the next seed replaces that page and
    /// no other at its address.
    static let looseArticleMarker = "debug.demo-book.loose-page"

    /// The offline test page of chapter `index` (0 is the title page).
    static func url(ofChapter index: Int) -> URL {
        URL(string: "reader-test://pages/book-\(index)")!
    }

    /// The test page `book-N`'s title and body, for `TestPageSchemeHandler`.
    static func testPage(_ name: String) -> (title: String, body: String)? {
        guard name.hasPrefix("book-"), let index = Int(name.dropFirst(5)), chapters.indices.contains(index) else {
            return nil
        }
        return (chapters[index].title, chapters[index].html)
    }
}
#endif
