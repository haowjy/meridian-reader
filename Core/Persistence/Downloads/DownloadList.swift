import Foundation

/// One thing the user downloaded: a page, or a folder (a book, a series, a folder of pages),
/// with the pages it covers and how far each one got. Downloading a page fetches its text when it
/// is only a link (saving it in place) and renders its whole audio in the download voice ahead of
/// time, so it plays offline.
///
/// The pages are listed when the download is asked for, in play order: a book's or series'
/// chapters that play and aren't finished, a folder's own pages in its sort (not its
/// subfolders'). Pages added to the folder later aren't covered until *Re-download*.
struct DownloadRecord: Codable, Equatable, Identifiable {
    enum Target: Codable, Hashable {
        case page(UUID)
        case folder(UUID)
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
    /// The title when it was asked for; screens show the page's or folder's current one.
    var title: String
    var addedAt: Date
    var isPaused = false
    var entries: [Entry]
    /// The cache voice key the user chose to keep after the voice changed (*Keep*): audio in it
    /// counts as done, not as a different voice.
    var keptVoice: String?

    /// Pages still to fetch or render.
    var hasQueuedPages: Bool { entries.contains { $0.state == .queued } }

    /// Pages that ended without their audio.
    var failedCount: Int { entries.filter { $0.state == .failed }.count }

    /// Pages whose turn has come and gone (done, speaking live or failed).
    var finishedCount: Int { entries.filter { $0.state != .queued }.count }

    /// Every page back in the queue (*Re-download*).
    mutating func requeue(_ keys: [UUID]) {
        entries = keys.map { Entry(key: $0) }
        keptVoice = nil
        isPaused = false
    }
}

/// The download list, kept as JSON in Application Support (`Downloads.json`), in the order the
/// downloads were asked for. Downloads render in that order, one page at a time.
final class DownloadListStore: Sendable {
    private let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Downloads.json")
    }

    init(url: URL = DownloadListStore.defaultURL) {
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
