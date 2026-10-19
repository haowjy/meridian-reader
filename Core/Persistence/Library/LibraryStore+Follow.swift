import Foundation
import SwiftData

/// What a followed story keeps (`Folder.sourceStateData` of a `FolderKind.series` folder).
struct FollowState: Codable, Equatable {
    /// The daily check reads the story's table of contents again (Unfollow turns it off; the
    /// chapters already added stay, and their text is still fetched).
    var isFollowing = true
    /// The last check that read the table of contents (the first is Follow's own read).
    var lastCheckedAt: Date?
    /// The last check that added chapters, and how many.
    var lastAddedAt: Date?
    var lastAddedCount = 0
    /// Every chapter address the table of contents has listed (canonical), kept or unchecked in
    /// Review: a check adds only the ones not in it, so an unchecked chapter stays skipped and one
    /// you deleted doesn't come back.
    var seen: [String] = []
}

extension Folder {
    /// A followed story's state; nil for any other folder.
    var followState: FollowState? {
        guard kind == .series, let data = sourceStateData else { return nil }
        return try? JSONDecoder().decode(FollowState.self, from: data)
    }

    /// The story's table of contents.
    var contentsURL: URL? { sourceURLString.flatMap(URL.init(string:)) }
}

/// Following a story (Follow): a folder (`FolderKind.series`) made from its table of contents,
/// one link page per chapter in the story's order, its state in `FollowState`. Chapters come in
/// as links in the Library; their text is fetched later, one at a time, and stored in place
/// (`storeFetchedText`), so a chapter is a page like any other once it has its text. Each change
/// is one edit: a save that fails is rolled back and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// Followed stories (Unfollowed ones too: their chapters are still fetched), oldest first.
    func stories() -> [Folder] {
        let series = FolderKind.series.rawValue
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.kindRaw == series },
                                                 sortBy: [SortDescriptor(\Folder.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The story whose table of contents is `url`, when it is followed already.
    func story(contentsURL url: URL) -> Folder? {
        let identifier = ArticleIdentity.canonicalURLString(from: url)
        return stories().first { $0.sourceIdentifier == identifier }
    }

    /// Follows `contents`: a folder named for the story in `parent` (nil: the top level), holding
    /// `kept` as link pages in the story's order. Every chapter it lists is seen, `kept` or not.
    func follow(_ contents: TableOfContents, keeping kept: [TableOfContents.Chapter], in parent: Folder?) throws -> Folder {
        try edit("follow") {
            let folder = Folder(name: contents.title, kind: .series, sortKey: nextFolderSortKey(in: parent), createdAt: now())
            folder.parent = parent
            folder.byline = contents.byline
            folder.sourceURLString = contents.url.absoluteString
            folder.sourceIdentifier = ArticleIdentity.canonicalURLString(from: contents.url)
            context.insert(folder)
            var state = FollowState(lastCheckedAt: now())
            state.seen = contents.chapters.map(\.canonicalURL)
            setFollowState(state, of: folder)
            for chapter in kept { addChapter(chapter, to: folder, byline: contents.byline) }
            log("follow \(folder.sourceIdentifier ?? "-"): \(kept.count) of \(contents.chapters.count) chapters")
            return folder
        }
    }

    /// A check read the story's table of contents again (`contents`): chapters it hasn't listed
    /// before go at the end of the folder, in the story's order. Returns how many.
    @discardableResult
    func addNewChapters(from contents: TableOfContents, to folder: Folder) throws -> Int {
        guard var state = folder.followState else { return 0 }
        let seen = Set(state.seen)
        let new = contents.chapters.filter { !seen.contains($0.canonicalURL) }
        try edit("check story") {
            for chapter in new { addChapter(chapter, to: folder, byline: folder.byline) }
            state.seen += new.map(\.canonicalURL)
            // One instant for both: the status line says "2 new" only while they are equal.
            let checked = now()
            state.lastCheckedAt = checked
            if !new.isEmpty {
                state.lastAddedAt = checked
                state.lastAddedCount = new.count
            }
            setFollowState(state, of: folder)
        }
        if !new.isEmpty { log("story \(Self.short(folder.id)): \(new.count) new chapters") }
        return new.count
    }

    /// Unfollow (false) or follow again: whether the daily check reads the story's table of
    /// contents. The chapters stay.
    func setFollowing(_ folder: Folder, _ following: Bool) throws {
        guard var state = folder.followState, state.isFollowing != following else { return }
        state.isFollowing = following
        try edit(following ? "follow again" : "unfollow") { setFollowState(state, of: folder) }
    }

    /// A chapter's text, fetched: the link page becomes a page with text, in place (its key,
    /// title and folder stay), and once stored its audio is the Library's (`plan(.saved, key:)`).
    /// Nothing renders here: whether it downloads is its folder's Download's to say.
    func storeFetchedText(_ content: PageContent, in page: Page) throws {
        try edit("chapter text") {
            page.setText(html: content.bodyHTML, plain: content.plainText, excerpt: content.excerpt,
                         paragraphs: content.document.paragraphs)
            if page.title.isEmpty { page.title = content.title }
            keepText(of: page)
        }
    }

    /// A link page holding the text it was played from keeps it as its own, without a fetch.
    func keepCachedText(_ page: Page) throws {
        try edit("keep link text") { keepText(of: page) }
    }

    private func keepText(of page: Page) {
        page.contentState = .saved
        if page.isInLibrary, let key = page.key { plan(.saved, key: key) }
    }

    /// One chapter at the end of `folder`. An address the library has already stays one page: one
    /// you filed in a folder stays there; one loose at the top level (saved to try the story) or
    /// out of the Library (played without saving, removed) comes into the story, so the story has
    /// every chapter.
    private func addChapter(_ chapter: TableOfContents.Chapter, to folder: Folder, byline: String?) {
        if let existing = page(canonicalURL: chapter.canonicalURL) {
            guard existing.folder == nil else { return }
            if existing.addedAt == nil {
                existing.addedAt = now()
                if existing.isSaved, let key = existing.key { plan(.saved, key: key) }
            }
            existing.sortKey = nextSortKey(in: folder)
            existing.setFolder(folder)
            return
        }
        let page = Page(key: ArticleIdentity.articleKey(canonicalURL: chapter.canonicalURL), title: chapter.title,
                        byline: byline ?? chapter.url.host ?? "", urlString: chapter.url.absoluteString,
                        contentState: .link, addedAt: now(), sortKey: nextSortKey(in: folder))
        context.insert(page)
        page.setFolder(folder)
    }

    private func setFollowState(_ state: FollowState, of folder: Folder) {
        folder.sourceStateData = try? JSONEncoder().encode(state)
    }
}
