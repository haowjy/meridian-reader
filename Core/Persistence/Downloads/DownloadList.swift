import Foundation

/// One thing the user downloaded: a page, or a folder (a book, a series, a folder of pages),
/// with the pages it covers and how far each one got. Downloading a page fetches its text when it
/// is only a link (saving it in place) and renders its whole audio in the download voice ahead of
/// time, so it plays offline.
///
/// The pages are listed when the download is asked for, in play order: a book's or story's
/// chapters that play and aren't finished, a folder's own pages in its sort (not its
/// subfolders'). A folder's download is its Download toggle: while it is on (`followsFolder`),
/// pages added to the folder later join it; turned off, nothing new joins and what is
/// downloaded stays.
struct DownloadRecord: Codable, Equatable, Identifiable {
    enum Target: Codable, Hashable {
        case page(UUID)
        case folder(UUID)

        var isFolder: Bool {
            if case .folder = self { return true }
            return false
        }
    }

    /// Where one page is. Raw values are persisted.
    enum PageState: String, Codable {
        /// Waiting its turn, or being fetched or rendered now.
        case queued
        /// Its audio was rendered in full (the voice is the audio cache's to say).
        case done
        /// Its language isn't one the on-device voice speaks: it plays with Apple's voice, which
        /// needs nothing downloaded.
        case speaksLive
        /// Couldn't be fetched, or some of its audio couldn't be rendered (`failure` says which).
        case failed
    }

    struct Entry: Codable, Equatable {
        var key: UUID
        var state: PageState = .queued
        var failure: String?
    }

    var id = UUID()
    var target: Target
    /// What named it when it was asked for (a page's `lineOne`, a folder's name); screens show
    /// the page's or folder's current one.
    var title: String
    var addedAt: Date
    var isPaused = false
    var entries: [Entry]
    /// The cache voice key the user chose to keep after the voice changed (*Keep*): audio in it
    /// counts as done, not as a different voice.
    var keptVoice: String?
    /// A folder's Download toggle is on: pages added to the folder later join this download.
    var followsFolder = true
    /// Pages of the folder whose downloads were deleted (*Delete Downloads* on one, decision P8):
    /// they don't join again while the toggle stays on, until Download is asked for again.
    var deleted: [UUID] = []

    init(target: Target, title: String, addedAt: Date, entries: [Entry]) {
        self.target = target
        self.title = title
        self.addedAt = addedAt
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id, target, title, addedAt, isPaused, entries, keptVoice, followsFolder, deleted
    }

    /// A list written before the toggle has neither of its fields: a folder's download asked for
    /// then is on, with nothing deleted.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        target = try values.decode(Target.self, forKey: .target)
        title = try values.decode(String.self, forKey: .title)
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        isPaused = try values.decode(Bool.self, forKey: .isPaused)
        entries = try values.decode([Entry].self, forKey: .entries)
        keptVoice = try values.decodeIfPresent(String.self, forKey: .keptVoice)
        followsFolder = try values.decodeIfPresent(Bool.self, forKey: .followsFolder) ?? true
        deleted = try values.decodeIfPresent([UUID].self, forKey: .deleted) ?? []
    }

    /// Pages still to fetch or render.
    var hasQueuedPages: Bool { entries.contains { $0.state == .queued } }

    /// Pages that ended without their audio.
    var failedCount: Int { entries.filter { $0.state == .failed }.count }

    /// Pages whose turn has come and gone (done, speaking live or failed).
    var finishedCount: Int { entries.filter { $0.state != .queued }.count }

    /// Audio in `voice` (a cache voice key) counts as this download's: it is the voice downloads
    /// render in now (`current`), or the one the user chose to keep (*Keep*).
    func accepts(_ voice: String, current: String?) -> Bool {
        voice == current || voice == keptVoice
    }

    /// This download has `key`'s page: its turn ended with the whole audio rendered (`.done`),
    /// and that audio is still there, in a voice the download accepts. What a row's Downloaded
    /// mark and a folder's Download button ask (`DownloadOverview.isDownloaded`).
    func hasDownloaded(_ key: UUID, current: String?, voiceOf: (UUID) -> String?) -> Bool {
        guard entries.contains(where: { $0.key == key && $0.state == .done }), let voice = voiceOf(key) else { return false }
        return accepts(voice, current: current)
    }

    /// A voice some of its done pages' audio is in that the download doesn't accept (the first by
    /// name), which puts it under *Different voice*; nil when every done page's audio, where it
    /// has any, is in an accepted voice.
    func otherVoice(current: String?, voiceOf: (UUID) -> String?) -> String? {
        entries.filter { $0.state == .done }.compactMap { voiceOf($0.key) }
            .filter { !accepts($0, current: current) }.sorted().first
    }

    /// Every page back in the queue (*Re-download*, Download asked for again): a folder's toggle
    /// on, its deleted pages taken back.
    mutating func requeue(_ keys: [UUID]) {
        entries = keys.map { Entry(key: $0) }
        keptVoice = nil
        isPaused = false
        followsFolder = true
        deleted = []
    }

    /// The folder's pages that join this download now (`covered`, in play order): those not in it
    /// and not deleted. None while the toggle is off.
    func joining(_ covered: [UUID]) -> [UUID] {
        guard followsFolder else { return [] }
        let known = Set(entries.map(\.key)).union(deleted)
        return covered.filter { !known.contains($0) }
    }
}

/// The download list, kept as JSON in Application Support (`Downloads.json`), in the order the
/// downloads were asked for. Downloads render in that order, one page at a time.
final class DownloadListStore: Sendable {
    private let url: URL

    init(url: URL = AppDirectories.downloads) {
        self.url = url
    }

    func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DownloadRecord].self, from: data)) ?? []
    }

    func save(_ records: [DownloadRecord]) {
        guard !records.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
