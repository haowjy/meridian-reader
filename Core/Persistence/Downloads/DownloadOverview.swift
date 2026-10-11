import Foundation

/// What the Downloads list and the progress line show, worked out from the download list, the
/// page being rendered now and the voice each page's audio is in. A pure value, so the rules are
/// tested without a library or a voice.
///
/// - **Queued**: downloads with pages still to fetch or render (the one rendering now first in
///   its place, paused ones too).
/// - **Done**: every page's turn has come, and the audio is in the download voice, or in a voice
///   the user chose to keep.
/// - **Different voice**: done, but some of its audio is in another voice than the one
///   downloads render in now (the voice changed since).
struct DownloadOverview: Equatable {
    enum Status: Equatable {
        /// One of its pages is being fetched or rendered now.
        case downloading(fraction: Double)
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
            case .downloading(let f), .queued(let f), .paused(let f), .waitingForVoice(let f): f
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
            if record.hasQueuedPages {
                let activeFraction = active?.recordID == record.id ? min(max(active?.fraction ?? 0, 0), 1) : 0
                let total = max(record.entries.count, 1)
                let fraction = (Double(record.finishedCount) + activeFraction) / Double(total)
                let status: Status
                if record.isPaused {
                    status = .paused(fraction: fraction)
                } else if !rendersDownloads {
                    status = .waitingForVoice(fraction: fraction)
                } else if active?.recordID == record.id {
                    status = .downloading(fraction: fraction)
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
            let accepted = Set([currentVoice, record.keptVoice].compactMap { $0 })
            if currentVoice != nil, let other = voices.subtracting(accepted).sorted().first {
                differentVoice.append(Item(record: record, status: .differentVoice(other), voice: other))
                continue
            }
            let named = voices.count == 1 ? voices.first : voices.first { $0 == currentVoice } ?? voices.sorted().first
            done.append(Item(record: record, status: .done, voice: named))
        }
        progress = runningTotal > 0 ? runningDone / Double(runningTotal) : nil
    }

    /// The progress line's value alone (`progress`), without reading any page's voice: cheap
    /// enough for every frame of the bottom chrome.
    static func progress(records: [DownloadRecord], active: Active?, rendersDownloads: Bool) -> Double? {
        DownloadOverview(records: records.filter { $0.hasQueuedPages }, active: active, currentVoice: nil,
                         rendersDownloads: rendersDownloads) { _ in nil }.progress
    }
}
