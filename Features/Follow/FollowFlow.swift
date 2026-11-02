import Foundation
import Observation

/// Add a Link and a known page’s Follow share one read, review and save flow.
@MainActor
@Observable
final class FollowFlow: Identifiable {
    enum Step {
        /// A folder's ⋯: the story's address is asked for.
        case address
        case saved
        /// Reading the table of contents at the address.
        case reading(URL)
        /// It couldn't be read, or listed no chapters.
        case failed(URL, message: String)
        /// The story is followed already, in this folder.
        case alreadyFollowing(UUID)
        /// Its chapters, to keep or leave out.
        case review(TableOfContents)
    }

    let id = UUID()
    /// Where the story's folder goes (nil: the Library's top level).
    let parentID: UUID?
    let isAddingLink: Bool
    private(set) var originalURL: URL?
    private(set) var saveError: String?
    private(set) var isSaving = false
    @ObservationIgnored private let saveKnownPage: (() async -> Bool)?
    private(set) var step: Step
    /// The address field, on the address step.
    var address: String
    /// The chapters kept (checked), by canonical address.
    private(set) var kept: Set<String> = []
    /// The chapter whose preview is up.
    private(set) var previewed: TableOfContents.Chapter?

    @ObservationIgnored private let center: FollowCenter
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// From the browser's page `url` (read at once), or from a folder (nil: its address is asked).
    init(url: URL?, parentID: UUID?, center: FollowCenter, savePage: (() async -> Bool)? = nil) {
        isAddingLink = url == nil
        originalURL = url
        saveKnownPage = savePage
        self.parentID = parentID
        self.center = center
        address = url?.absoluteString ?? ""
        step = .address
        if let url { read(url) }
    }

    /// The address field as an address: a scheme is added when it has none.
    var typedURL: URL? {
        #if DEBUG
        if let url = URL(string: address), url.scheme == "reader-test", url.host != nil { return url }
        #endif
        return LibraryScreenState.linkURL(address)
    }

    // MARK: - Reading

    /// Reads the story `url` belongs to; a story followed already shows as that.
    func read(_ url: URL) {
        reading?.cancel()
        originalURL = url
        saveError = nil
        step = .reading(TableOfContents.contentsURL(for: url))
        reading = Task {
            do {
                let contents = try await center.readContents(of: url)
                guard !Task.isCancelled else { return }
                if let folder = center.library.story(contentsURL: contents.url) {
                    step = .alreadyFollowing(folder.id)
                } else {
                    kept = Set(contents.chapters.map(\.canonicalURL))
                    step = .review(contents)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                step = .failed(url, message: FollowCenter.message(for: error))
                if isAddingLink { await savePage() }
            }
        }
    }

    /// Save the original page, never the contents URL a chapter resolved to. A failed
    /// store write keeps the sheet and its input available for another attempt.
    func savePage() async {
        guard !isSaving, let url = originalURL else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        if let saveKnownPage {
            if await saveKnownPage() { step = .saved }
            else { saveError = String(localized: "Couldn’t save. Try again.") }
        } else {
            do {
                try center.library.saveLink(url, in: parentID.flatMap(center.library.folder(id:)))
                step = .saved
            } catch {
                saveError = String(localized: "Couldn’t save. Try again.")
            }
        }
    }

    /// The sheet went away: nothing it started carries on.
    func cancel() {
        reading?.cancel()
    }

    // MARK: - Review

    func isKept(_ chapter: TableOfContents.Chapter) -> Bool {
        kept.contains(chapter.canonicalURL)
    }

    func toggle(_ chapter: TableOfContents.Chapter) {
        if kept.remove(chapter.canonicalURL) == nil { kept.insert(chapter.canonicalURL) }
    }

    /// *Select All*: everything kept, or, when everything is, nothing.
    func toggleAll(in contents: TableOfContents) {
        kept = kept.count == contents.chapters.count ? [] : Set(contents.chapters.map(\.canonicalURL))
    }

    /// The chapters kept, in the story's order.
    func keptChapters(of contents: TableOfContents) -> [TableOfContents.Chapter] {
        contents.chapters.filter(isKept)
    }

    /// The story's folder, made at once with the chapters kept, which start fetching.
    func follow(_ contents: TableOfContents, in parent: Folder?) throws -> Folder {
        try center.follow(contents, keeping: keptChapters(of: contents), in: parent)
    }

    // MARK: - Preview

    /// A chapter row's tap: its page, in the preview (`FollowPreviewSheet`).
    func showPreview(of chapter: TableOfContents.Chapter) {
        previewed = chapter
    }

    /// The preview went down.
    func closePreview() {
        previewed = nil
    }
}

extension FollowFlow: Equatable {
    nonisolated static func == (a: FollowFlow, b: FollowFlow) -> Bool { a === b }
}
