import Foundation
import SwiftData

/// What a `LibraryAudioWork` does. Raw values are persisted.
enum LibraryAudioWorkKind: String, Codable {
    /// A page's listen paragraphs were rebuilt (the layout pass): its audio follows them.
    case align
    /// Dedupe merged one page into another: the merged page's audio moves under the kept key.
    case merge
    /// A page was deleted (a row's *Delete*, *Delete Folder and Contents*, *Delete Book*, or a
    /// chapter a book's *Replace* dropped): its audio, its pending render and its queued renders
    /// go, unless a page with its key is back by the time it runs.
    case delete
    /// A page left the Library (*Remove from Library*, unsave): its audio goes back on the
    /// ephemeral TTL, kept for playback until the audio cache's age prune, unless the page is
    /// saved in the Library again by the time it runs.
    case ephemeral
    /// A page was saved to the Library (Save): its audio is marked saved, out of the ephemeral
    /// TTL, and its queued render turns non-ephemeral, if the page is still saved in the Library
    /// when it runs.
    case saved
}

/// Work outside the library store that a library change needs once it is saved: the audio cache,
/// pending renders and the crash-resume point. Recorded in the same save as the change, done
/// right after it (`LibraryStore.commit`), and deleted once its postconditions hold on disk. Work
/// that fails, or that a launch died in the middle of, stays here and the next launch does it
/// before anything touches the cache (`LibraryStore.finishAudioWork`); every step is idempotent.
/// A save that fails leaves the files as they were. Device-local, like the audio cache.
@Model
final class LibraryAudioWork {
    /// Done in this order.
    var sequence: Int = 0
    var kindRaw: String = LibraryAudioWorkKind.align.rawValue
    /// The page whose audio ends up aligned: the rebuilt page, or the page kept by a merge; for
    /// `delete`, the deleted page; for `ephemeral`, the page that left the Library; for `saved`,
    /// the page saved.
    var key: UUID?
    /// `merge`: the merged page, whose audio moves under `key`.
    var fromKey: UUID?
    /// The paragraphs `key`'s audio is aligned to (JSON `[String]`).
    @Attribute(.externalStorage) var paragraphsData: Data?
    /// The paragraphs the moving audio and position are on: the page's old paragraphs (`align`),
    /// or the merged page's (`merge`). JSON `[String]`.
    @Attribute(.externalStorage) var sourceParagraphsData: Data?
    /// Stamp the moving audio's unhashed entries with `sourceParagraphsData` first (false when an
    /// earlier `align` already did, in the old numbering).
    var stampsSource: Bool = true
    /// `merge`: stamp the kept page's unhashed entries with `paragraphsData` first.
    var stampsTarget: Bool = true
    /// The crash-resume point this work moves, as it was planned to be found (paragraph and
    /// time, on the source key); nil when it named another page.
    var resumeParagraph: Int?
    var resumeAt: Date?

    init(sequence: Int, kind: LibraryAudioWorkKind, key: UUID, fromKey: UUID? = nil,
         paragraphs: [String], sourceParagraphs: [String]) {
        self.sequence = sequence
        self.kindRaw = kind.rawValue
        self.key = key
        self.fromKey = fromKey
        self.paragraphsData = try? JSONEncoder().encode(paragraphs)
        self.sourceParagraphsData = try? JSONEncoder().encode(sourceParagraphs)
    }

    var kind: LibraryAudioWorkKind? { LibraryAudioWorkKind(rawValue: kindRaw) }
    /// The key the moving audio and the resume point are on now.
    var sourceKey: UUID? { fromKey ?? key }
    var paragraphs: [String] { Page.decodeAnyListenParagraphs(paragraphsData) ?? [] }
    var sourceParagraphs: [String] { Page.decodeAnyListenParagraphs(sourceParagraphsData) ?? [] }
}
