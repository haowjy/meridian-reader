import SwiftUI

/// Where a page's or folder's prepare stands (`PrepareCenter.state(of:)`): what its row's mark,
/// its menu's *Prepare* / *Remove Prepared Audio* and a folder header's Prepare control show.
enum PrepareState: Equatable {
    /// Not prepared and not queued.
    case notPrepared
    /// Rendering now: how much of it is ready, 0…1 (a page's paragraphs rendered of its total; a
    /// folder's pages and the one rendering, `PrepareOverview.fraction`).
    case preparing(fraction: Double)
    /// Waiting its turn behind another prepare (not paused): how much of it is ready, 0…1. Drawn
    /// as the spinning arc, never filling, so only what renders now fills (C90).
    case queued(fraction: Double)
    /// Queued, and its prepare paused: drawn as preparing, in grey, everywhere it shows (a
    /// row's tile, a folder header's control, the Prepared Audio list).
    case paused(fraction: Double)
    /// Every page it covers is prepared (in the prepare voice, or one its prepare kept).
    case prepared

    /// Preparing or paused: it has pages still to prepare.
    var isPreparing: Bool {
        switch self {
        case .preparing, .queued, .paused: true
        default: false
        }
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// "Prepare Audio", "Preparing", "Prepared": a header control's caption and VoiceOver label.
    var label: String {
        switch self {
        case .notPrepared: Verbs.prepare
        case .preparing: String(localized: "Preparing")
        case .queued: String(localized: "Waiting")
        case .paused: String(localized: "Paused")
        case .prepared: Verbs.prepared
        }
    }

    /// Waiting its turn.
    var isQueued: Bool { if case .queued = self { true } else { false } }

    /// How much is ready while preparing, waiting or paused; nil otherwise.
    var fraction: Double? {
        switch self {
        case .preparing(let f), .queued(let f), .paused(let f): f
        default: nil
        }
    }

    /// Its `DownloadMark`: ◯↓, the spinning arc while it waits its turn, the ring filling while it
    /// renders (grey while paused), ●↓ once prepared.
    var mark: DownloadMark.State {
        switch self {
        case .notPrepared: .idle
        case .queued: .waiting
        case .preparing(let fraction): .progress(fraction)
        case .paused(let fraction): .paused(fraction)
        case .prepared: .done
        }
    }

    /// "40 percent" while preparing; "" otherwise.
    var percentText: String {
        switch self {
        case .preparing(let fraction), .queued(let fraction), .paused(let fraction):
            String(localized: "\(Int((fraction * 100).rounded())) percent")
        default: ""
        }
    }
}
