import Foundation

/// A page has a title only when its source gives it one: a web page's own (its `<title>` or
/// heading, as Readability reads them), a book chapter's contents entry or heading, a story's
/// chapter link. Nothing makes one up: no "Untitled", no first words, no "Chapter 6", no file
/// name. In the domain and the views a title is `String?` (nil: none); the library stores none
/// as "" (`Page.title`, `RecentVisit.title`).
///
/// The Reader's heading and Now Playing's title card show a title only when there is one. What
/// must name a page in one line (a row, a Favorites tile, the Now Playing bar, the lock screen, a
/// download, a toast) uses `lineOne`, and only that.
enum PageTitle {
    /// The page's title, else its source (its site, or the book or series a chapter is in), else
    /// its address.
    static func lineOne(title: String?, source: String?, address: String?) -> String {
        [title, source, address].lazy.compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    /// The source as line two's first part, after `lineOne`: nil when there is no title, since
    /// line one already is the source then (or when there is no source).
    static func lineTwoSource(title: String?, source: String?) -> String? {
        guard let title, !title.isEmpty, let source, !source.isEmpty else { return nil }
        return source
    }

    /// What a page's artwork shows the first letter of when it has no picture: its source, else
    /// its title, else its address.
    static func artworkLetter(title: String?, source: String?, address: String?) -> String {
        [source, title, address].lazy.compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
}
