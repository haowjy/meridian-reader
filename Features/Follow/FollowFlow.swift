import Foundation
import Observation

/// Add a Link and a known page’s Follow share one read, review and save flow.
@MainActor
@Observable
final class FollowFlow: Identifiable {
    enum Step {
        /// Add a Link: the address is asked for.
        case address
        /// The page is saved (or was in the Library already): the sheet closes.
        case saved
        /// Reading the table of contents at the address.
        case reading(URL)
        /// It couldn't be read, or listed nothing to follow.
        case failed(URL, message: String)
        /// The story is followed already, in this folder.
        case alreadyFollowing(UUID)
        /// Its chapters or posts, to keep or leave out.
        case review(TableOfContents)
    }

    let id = UUID()
    /// The folder Add a Link saves a plain link into (nil: the top level). A followed story's
    /// folder always goes to the top level.
    let linkFolderID: UUID?
    let isAddingLink: Bool
    private(set) var originalURL: URL?
    private(set) var saveError: String?
    private(set) var isSaving = false
    /// Add a Link's address was in the Library already: it stayed where it was, and nothing was saved.
    private(set) var wasInLibrary = false
    /// A known page's save (the browser's extracts the page first, so it can take a while). It
    /// throws to say why it couldn't, and stores nothing once cancelled.
    @ObservationIgnored private let saveKnownPage: (() async throws -> Void)?
    private(set) var step: Step
    /// The address field, on the address step.
    var address: String
    /// The chapters kept (checked), by canonical address.
    private(set) var kept: Set<String> = []
    /// The chapter whose preview is up.
    private(set) var previewed: TableOfContents.Chapter?

    @ObservationIgnored private let center: FollowCenter
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?

    /// A known page's *Follow…* (`url`, read at once, saved by `savePage`), or Add a Link (`url` nil:
    /// the address is asked, a plain link saved into `linkFolderID`).
    init(url: URL?, linkFolderID: UUID? = nil, center: FollowCenter, savePage: (() async throws -> Void)? = nil) {
        isAddingLink = url == nil
        originalURL = url
        saveKnownPage = savePage
        self.linkFolderID = linkFolderID
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

    /// Reads what `url` lists to follow; a story followed already shows as that.
    func read(_ url: URL) {
        reading?.cancel()
        originalURL = url
        saveError = nil
        step = .reading(url)
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
                if isAddingLink { savePage() }
            }
        }
    }

    /// *Save This Page Only* (and Add a Link's save once the read fails): the original page, never
    /// the contents URL a chapter resolved to. It never moves a page the Library has: Add a Link's
    /// address already there stays in its folder (`wasInLibrary`), and a known page saves where
    /// the Library keeps it. A failed save keeps the sheet up with its reason, for another try.
    func savePage() {
        guard !isSaving, let url = originalURL else { return }
        isSaving = true
        saveError = nil
        saving = Task {
            defer { isSaving = false }
            do {
                if let saveKnownPage {
                    try await saveKnownPage()
                } else if center.library.article(url: url)?.isInLibrary == true {
                    wasInLibrary = true
                } else {
                    try center.library.saveLink(url, in: linkFolderID.flatMap(center.library.folder(id:)))
                }
                guard !Task.isCancelled else { return }
                step = .saved
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                saveError = Self.message(for: error)
            }
        }
    }

    /// Why a save failed, in the sheet's error line: the page's own reason (it changed, nothing to
    /// read on it), else a store failure's plain line.
    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn’t save. Try again.")
    }

    /// The sheet went away (✕, a pull): nothing it started carries on, and a save under way
    /// stores nothing.
    func cancel() {
        reading?.cancel()
        saving?.cancel()
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

    /// The story's folder, made at once at the Library's top level with the chapters kept, which
    /// start fetching.
    func follow(_ contents: TableOfContents) throws -> Folder {
        try center.follow(contents, keeping: keptChapters(of: contents), in: nil)
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
