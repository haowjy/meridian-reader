import Foundation
import Observation

/// One use of the Follow sheet (`ShellSheet.follow`): from an address (the browser's page, or one
/// pasted from a folder's ⋯) to the story's table of contents, then Review, then OK. The sheet
/// draws whichever step it is on; the steps change only here.
@MainActor
@Observable
final class FollowFlow: Identifiable {
    enum Step {
        /// A folder's ⋯: the story's address is asked for.
        case address
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
    init(url: URL?, parentID: UUID?, center: FollowCenter) {
        self.parentID = parentID
        self.center = center
        address = url?.absoluteString ?? ""
        step = .address
        if let url { read(url) }
    }

    /// The address field as an address: a scheme is added when it has none.
    var typedURL: URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    // MARK: - Reading

    /// Reads the story `url` belongs to; a story followed already shows as that.
    func read(_ url: URL) {
        reading?.cancel()
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
            }
        }
    }

    /// Back to the address step (a folder's ⋯, after a failed read).
    func editAddress() {
        reading?.cancel()
        step = .address
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

    /// OK: the story's folder, made at once with the chapters kept, which start fetching.
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
