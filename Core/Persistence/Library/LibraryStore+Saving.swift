import Foundation
import SwiftData

/// Saving a page that isn't a web page's extraction: a page played without saving filed into the
/// Library, an address saved as a link, and pasted text.
extension LibraryStore {
    /// Add a Link (C126): the page for `url` saved in `folder` (nil: the top level), at its end. One
    /// already in the Library stays in its folder (a followed story's chapter stays in its story);
    /// one the library has outside it (played without saving) goes in; a new one is a link page,
    /// whose text is fetched when it first plays or prepared audio.
    @discardableResult
    func saveLink(_ url: URL, in folder: Folder?) throws -> Article {
        let existing = article(url: url)
        let saved = try edit("save link") { () -> Article in
            if let existing {
                if existing.addedAt == nil {
                    existing.addedAt = now()
                    existing.removedAt = nil
                    existing.sortKey = nextSortKey(in: folder)
                    existing.setFolder(folder)
                }
                return existing
            }
            let canonical = ArticleIdentity.canonicalURLString(from: url)
            let article = Article(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: "",
                                  byline: url.host ?? url.absoluteString, urlString: url.absoluteString,
                                  contentState: .link, addedAt: now(), sortKey: nextSortKey(in: folder))
            context.insert(article)
            article.setFolder(folder)
            return article
        }
        if let key = saved.key { plan(.saved, key: key) }
        return saved
    }

    /// *Paste Text…* (C127): a new article holding `text`, saved at the end of `folder` (nil: the
    /// top level). It has no web address (`ArticleOrigin.book`, locator "text:<key>"), so nothing
    /// ever refetches it; it reads, plays and prepared audio like any saved article.
    ///
    /// A first line that is the title (the untitled paste's whole first line, or one matching the
    /// typed title) is its heading, not text: it is left out of the paragraphs, as a web page's
    /// heading matching its title is. A one-line paste keeps its line, and a title cut from a
    /// longer first line (`defaultTitle`) leaves that line in.
    ///
    /// `key`: the page's key when it must be a known one (a bundled article whose audio ships
    /// with the app, `WelcomeArticle`); a page already holding it comes back into the Library as
    /// it is, text and position kept. `atTop`: it goes before the folder's first page, not after
    /// its last. `byline` is a new page's; a page already holding `key` keeps its own.
    @discardableResult
    func saveText(title: String, text: String, in folder: Folder?, key: UUID = UUID(), atTop: Bool = false,
                  byline: String = String(localized: "Pasted text")) throws -> Article {
        let plain = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks = plain.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? Self.defaultTitle(for: plain) : typed
        if blocks.count > 1, blocks[0] == name { blocks.removeFirst() }
        let body = blocks.joined(separator: "\n\n")
        let html = blocks.map { "<p>" + Self.escapedHTML($0) + "</p>" }.joined(separator: "\n")
        let paragraphs = Article.buildListenDocument(plainText: body, cleanedHTML: html, title: nil).paragraphs
        let saved = try edit("paste text") { () -> Article in
            let sortKey = atTop ? firstSortKey(in: folder) - 1 : nextSortKey(in: folder)
            if let existing = self.article(key: key) {
                if existing.addedAt == nil {
                    existing.addedAt = now()
                    existing.removedAt = nil
                    existing.sortKey = sortKey
                    existing.setFolder(folder)
                }
                return existing
            }
            let article = Article(key: key, title: name, byline: byline, urlString: nil,
                                  contentState: .saved, addedAt: now(), sortKey: sortKey)
            article.givenTitle = name
            article.locator = "text:\(key.uuidString)"
            article.setText(html: html, plain: body, excerpt: String(body.prefix(140)),
                            paragraphs: paragraphs)
            context.insert(article)
            article.setFolder(folder)
            return article
        }
        if let key = saved.key { plan(.saved, key: key) }
        return saved
    }

    /// A pasted text's title when none is typed: its first line, cut at its first sentence's end,
    /// at most 80 characters.
    nonisolated static func defaultTitle(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var sentence = line
        if let end = line.firstIndex(where: { ".!?".contains($0) }), line.index(after: end) < line.endIndex {
            sentence = String(line[...end])
        }
        if sentence.count > 80 { sentence = String(sentence.prefix(79)).trimmingCharacters(in: .whitespaces) + "…" }
        return sentence.isEmpty ? String(localized: "Pasted Text") : sentence
    }

    nonisolated static func escapedHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// *Prepare* on a page played without saving saves it first (C104), into the Library's top
    /// level; a page in the Library stays where it is.
    func saveUnsaved(_ article: Article) throws {
        guard article.addedAt == nil else { return }
        try edit("save to download") {
            article.addedAt = now()
            article.removedAt = nil
            article.sortKey = nextSortKey(in: nil)
        }
    }
}
