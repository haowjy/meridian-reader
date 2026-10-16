import Foundation

extension Page {
    /// Where its text comes from: its web address when it has one (a book chapter with one is a
    /// web page too), else its place in its book.
    var origin: PageOrigin {
        guard let url else { return .book(locator: locator ?? "") }
        return .web(url, canonicalURL: canonicalURL ?? ArticleIdentity.canonicalURLString(from: url))
    }

    /// The page's listen / audio cache key. Every page `LibraryStore` makes has one; a page
    /// synced without it would use its address's key.
    var listenKey: UUID {
        key ?? ArticleIdentity.articleKey(canonicalURL: origin.canonicalURL ?? title)
    }

    /// Where listening to the page starts: its saved spot, or its top once it is finished.
    var listenStart: ListenSpot {
        finishedAt == nil ? ListenSpot(paragraph: positionParagraph, utf16Offset: positionUTF16) : .top
    }

    /// Saved in the Library: what the reader's 🔖 and ⋯ → Save show as saved. A link (a favorite
    /// only) or a page played without saving isn't.
    var isSavedToLibrary: Bool { isSaved && isInLibrary }
}
