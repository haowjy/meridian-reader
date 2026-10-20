import Foundation

/// What the Downloads list and the progress line show, worked out from the download list, the
/// page being rendered now and the voice each page's audio is in. A pure value, so the rules are
/// tested without a library or a voice.
///
/// - **Queued**: downloads with pages still to fetch or render (the one rendering now first in
///   its place, paused ones too).
/// - **Done**: every page's turn has come, and the audio is in a voice the download accepts
///   (`DownloadRecord.accepts`): the download voice, or a voice the user chose to keep.
/// - **Different voice**: done, but some of its audio is in a voice it doesn't accept (the voice
///   changed since).
///
/// A row's Downloaded mark follows the same rule, per page (`isDownloaded`).
struct DownloadOverview: Equatable {
    enum Status: Equatable {
        /// One of its pages is being rendered now.
        case downloading(fraction: Double)
        /// One of its pages, a link, is having its text fetched now.
        case fetching(fraction: Double)
        /// Waiting its turn.
        case queued(fraction: Double)
        case paused(fraction: Double)
        /// No on-device voice is selected that renders downloads (Apple's voice speaks live).
        case waitingForVoice(fraction: Double)
        case done
        /// Done, with audio in this voice (a cache voice key) rather than the download voice.
        case differentVoice(String)

        var fraction: Double? {
            switch self {
            case .downloading(let f), .fetching(let f), .queued(let f), .paused(let f), .waitingForVoice(let f): f
            case .done, .differentVoice: nil
            }
        }
    }

    struct Item: Equatable, Identifiable {
        let record: DownloadRecord
        let status: Status
        /// The voice to name with it (a cache voice key): the one it renders in while queued, the
        /// one its audio is in once done. nil: no voice to name (no audio left, or no on-device
        /// voice).
        let voice: String?

        var id: UUID { record.id }
    }

    /// The page being fetched or rendered now, and how much of its audio is ready (0…1).
    struct Active: Equatable {
        var recordID: UUID
        var key: UUID
        var fraction: Double
        /// Its text is being fetched (a link page), before anything renders.
        var isFetching = false
    }

    var queued: [Item] = []
    var done: [Item] = []
    var differentVoice: [Item] = []
    /// The progress line's value (0…1) while downloads are running; nil hides it (nothing queued,
    /// everything queued is paused, or no voice renders downloads).
    var progress: Double?

    var isEmpty: Bool { queued.isEmpty && done.isEmpty && differentVoice.isEmpty }

    /// - Parameters:
    ///   - currentVoice: the cache voice key downloads render in now; nil: no on-device voice.
    ///   - rendersDownloads: an on-device voice that renders downloads is selected.
    ///   - voiceOf: the voice a page's audio is in (its key), nil when it has none.
    init(records: [DownloadRecord], active: Active?, currentVoice: String?, rendersDownloads: Bool,
         voiceOf: (UUID) -> String?) {
        var runningDone = 0.0
        var runningTotal = 0
        for record in records {
            // A folder's toggle turned on with nothing in it yet (a story you're caught up on):
            // not a download to list until a page joins it.
            guard !record.entries.isEmpty else { continue }
            if record.hasQueuedPages {
                let activeFraction = Self.activeFraction(of: record, active: active)
                let total = max(record.entries.count, 1)
                let fraction = Self.fraction(of: record, active: active)
                let status: Status
                if record.isPaused {
                    status = .paused(fraction: fraction)
                } else if !rendersDownloads {
                    status = .waitingForVoice(fraction: fraction)
                } else if let active, active.recordID == record.id {
                    status = active.isFetching ? .fetching(fraction: fraction) : .downloading(fraction: fraction)
                } else {
                    status = .queued(fraction: fraction)
                }
                if !record.isPaused, rendersDownloads {
                    runningDone += Double(record.finishedCount) + activeFraction
                    runningTotal += total
                }
                queued.append(Item(record: record, status: status, voice: currentVoice))
                continue
            }
            let voices = Set(record.entries.filter { $0.state == .done }.compactMap { voiceOf($0.key) })
            if currentVoice != nil, let other = record.otherVoice(current: currentVoice, voiceOf: voiceOf) {
                differentVoice.append(Item(record: record, status: .differentVoice(other), voice: other))
                continue
            }
            let named = voices.count == 1 ? voices.first : voices.first { $0 == currentVoice } ?? voices.sorted().first
            done.append(Item(record: record, status: .done, voice: named))
        }
        progress = runningTotal > 0 ? runningDone / Double(runningTotal) : nil
    }

    /// How much of `record` is ready, 0…1: its finished pages and how far the one rendering is.
    static func fraction(of record: DownloadRecord, active: Active?) -> Double {
        (Double(record.finishedCount) + activeFraction(of: record, active: active)) / Double(max(record.entries.count, 1))
    }

    private static func activeFraction(of record: DownloadRecord, active: Active?) -> Double {
        active?.recordID == record.id ? min(max(active?.fraction ?? 0, 0), 1) : 0
    }

    /// Whether every one of `keys` is downloaded: a download has its page
    /// (`DownloadRecord.hasDownloaded`: done, its audio there, in the download voice or one that
    /// download keeps), as the Downloads list counts it under *Downloaded* (`done`). Empty `keys`: false.
    static func isDownloaded(_ keys: [UUID], records: [DownloadRecord], currentVoice: String?,
                             voiceOf: (UUID) -> String?) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { key in
            records.contains { $0.hasDownloaded(key, current: currentVoice, voiceOf: voiceOf) }
        }
    }

    /// The progress line's value alone (`progress`), without reading any page's voice: cheap
    /// enough for every frame of the bottom chrome.
    static func progress(records: [DownloadRecord], active: Active?, rendersDownloads: Bool) -> Double? {
        DownloadOverview(records: records.filter { $0.hasQueuedPages }, active: active, currentVoice: nil,
                         rendersDownloads: rendersDownloads) { _ in nil }.progress
    }
}

/// The Downloads list by page (C110): each page of every download its own row, a folder's pages
/// too, never a folder total. A page in more than one download shows once, where it is furthest
/// from done (queued over finished). Queued pages are in the order they render (the downloads in
/// the order asked for, each one's pages in play order, as `DownloadCenter.nextQueued` takes them).
struct DownloadPages: Equatable {
    struct Item: Equatable, Identifiable {
        /// The download it came from (its *Keep*, and the remove when the page has gone).
        let recordID: UUID
        let key: UUID
        let status: DownloadOverview.Status
        /// It ended without its audio.
        var failed = false
        let voice: String?

        var id: UUID { key }
    }

    var now: [Item] = []
    var waiting: [Item] = []
    var done: [Item] = []
    var differentVoice: [Item] = []

    var isEmpty: Bool { now.isEmpty && waiting.isEmpty && done.isEmpty && differentVoice.isEmpty }

    init(records: [DownloadRecord], active: DownloadOverview.Active?, currentVoice: String?, rendersDownloads: Bool,
         voiceOf: (UUID) -> String?) {
        var seen = Set<UUID>()
        // Queued pages first, in render order.
        for record in records where !record.isPaused {
            for entry in record.entries where entry.state == .queued && seen.insert(entry.key).inserted {
                add(record, entry.key, rendersDownloads: rendersDownloads, active: active, currentVoice: currentVoice)
            }
        }
        for record in records where record.isPaused {
            for entry in record.entries where entry.state == .queued && seen.insert(entry.key).inserted {
                waiting.append(Item(recordID: record.id, key: entry.key, status: .paused(fraction: 0), voice: currentVoice))
            }
        }
        for record in records {
            for entry in record.entries where entry.state != .queued && seen.insert(entry.key).inserted {
                let voice = voiceOf(entry.key)
                if let voice, currentVoice != nil, !record.accepts(voice, current: currentVoice) {
                    differentVoice.append(Item(recordID: record.id, key: entry.key, status: .differentVoice(voice), voice: voice))
                } else {
                    done.append(Item(recordID: record.id, key: entry.key, status: .done, failed: entry.state == .failed,
                                     voice: voice))
                }
            }
        }
    }

    private mutating func add(_ record: DownloadRecord, _ key: UUID, rendersDownloads: Bool,
                              active: DownloadOverview.Active?, currentVoice: String?) {
        if let active, active.key == key, active.recordID == record.id {
            let f = min(max(active.fraction, 0), 1)
            now.append(Item(recordID: record.id, key: key,
                            status: active.isFetching ? .fetching(fraction: f) : .downloading(fraction: f), voice: currentVoice))
        } else {
            waiting.append(Item(recordID: record.id, key: key,
                                status: rendersDownloads ? .queued(fraction: 0) : .waitingForVoice(fraction: 0),
                                voice: currentVoice))
        }
    }
}
