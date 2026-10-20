import SwiftUI

/// Where a page's or folder's download stands (`DownloadCenter.state(of:)`): what its row's mark,
/// its menu's *Download* / *Remove Download* and a folder header's Download control show.
enum DownloadState: Equatable {
    /// Not downloaded and not queued.
    case notDownloaded
    /// Rendering now: how much of it is ready, 0…1 (a page's paragraphs rendered of its total; a
    /// folder's pages and the one rendering, `DownloadOverview.fraction`).
    case downloading(fraction: Double)
    /// Waiting its turn behind another download (not paused): how much of it is ready, 0…1. Drawn
    /// as a small spinner (an hourglass with Reduce Motion), never filling, so only what renders now fills (C90, C93).
    case queued(fraction: Double)
    /// Queued, and its download paused: drawn as downloading, in grey, everywhere it shows (a
    /// row's tile, a folder header's control, the Downloads list).
    case paused(fraction: Double)
    /// Every page it covers is downloaded (in the download voice, or one its download kept).
    case downloaded

    /// Downloading or paused: it has pages still to download.
    var isDownloading: Bool {
        switch self {
        case .downloading, .queued, .paused: true
        default: false
        }
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// "Download", "Downloading", "Downloaded": a header control's caption and VoiceOver label.
    var label: String {
        switch self {
        case .notDownloaded: Verbs.download
        case .downloading: String(localized: "Downloading")
        case .queued: String(localized: "Waiting")
        case .paused: String(localized: "Paused")
        case .downloaded: Verbs.downloaded
        }
    }

    /// Waiting its turn.
    var isQueued: Bool { if case .queued = self { true } else { false } }

    /// How much is ready while downloading, waiting or paused; nil otherwise.
    var fraction: Double? {
        switch self {
        case .downloading(let f), .queued(let f), .paused(let f): f
        default: nil
        }
    }

    /// "40 percent" while downloading; "" otherwise.
    var percentText: String {
        switch self {
        case .downloading(let fraction), .queued(let fraction), .paused(let fraction):
            String(localized: "\(Int((fraction * 100).rounded())) percent")
        default: ""
        }
    }
}

/// Download progress, drawn one way app-wide (rings mean listening only): an outline ↓ before it
/// downloads, the circle filling with the accent from the bottom as it downloads (the ↓ turning
/// white where the fill has reached it), the same in grey while paused, a small spinner
/// while it waits its turn (C93: `QueuedIndicator`, a small spinner), a accent filled ↓ once downloaded (C89: ✓ is selection's only). A
/// folder header's Download control, a row's tile while it downloads, a download in the
/// Downloads list, a voice model in Settings. Only draws; the caller makes it a button.
///
/// | notDownloaded | queued | downloading(0.4) | downloaded |
/// |---|---|---|---|
/// | ◯↓ secondary | spinner (⌛ Reduce Motion) | ◯↓ 40% filled | ● ↓ secondary |
struct DownloadMark: View {
    let state: DownloadState
    var size: CGFloat = Glyph.control

    var body: some View {
        ZStack {
            switch state {
            case .notDownloaded:
                Circle().strokeBorder(Palette.secondaryInk, lineWidth: lineWidth)
                arrow.foregroundStyle(Palette.secondaryInk)
            case .queued:
                QueuedIndicator(size: size * 0.7)
            case .downloading(let fraction), .paused(let fraction):
                let filled = size * min(max(fraction, 0), 1)
                let tint = state.isPaused ? Palette.secondaryInk : Palette.accent
                Circle().strokeBorder(tint, lineWidth: lineWidth)
                Circle().fill(tint).mask(alignment: .bottom) { Rectangle().frame(height: filled) }
                arrow.foregroundStyle(tint)
                arrow.foregroundStyle(Palette.onAccent).mask(alignment: .bottom) { Rectangle().frame(height: filled) }
            case .downloaded:
                Image(systemName: Icons.downloaded)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.standard, value: state)
        .accessibilityHidden(true)
    }

    private var lineWidth: CGFloat { max(1.5, size / 16) }

    private var arrow: some View {
        Image(systemName: Icons.downloadArrow)
            .font(.system(size: size * 0.5, weight: .bold))
    }
}

#if DEBUG
struct DownloadMarkGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("not downloaded, downloading 0%, 40%, 85%, downloaded") {
                HStack(spacing: Spacing.m) {
                    DownloadMark(state: .notDownloaded)
                    DownloadMark(state: .downloading(fraction: 0))
                    DownloadMark(state: .downloading(fraction: 0.4))
                    DownloadMark(state: .downloading(fraction: 0.85))
                    DownloadMark(state: .queued(fraction: 0.3))
                    DownloadMark(state: .downloaded)
                }
            }
            PreviewState("paused at 60%") {
                DownloadMark(state: .paused(fraction: 0.6))
            }
            PreviewState("small (a voice model in Settings)") {
                DownloadMark(state: .downloading(fraction: 0.3), size: 24)
            }
        }
    }
}

#Preview("DownloadMark · light", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.light) }
#Preview("DownloadMark · dark", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.dark) }
#Preview("DownloadMark · AX5", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.largestText) }
#endif

/// Waiting its turn to download (C93), as music apps mark a queued track: a small activity
/// spinner in the accent (spokes, never a circle, so it can't read as a listening ring, which
/// lives in a row's right column), and a still accent hourglass when Reduce Motion is on. A
/// queued row's badge slot before its line two, a waiting download in the Downloads list.
struct QueuedIndicator: View {
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: Icons.downloadQueued)
                    .font(.system(size: size * 0.85, weight: .medium))
                    .foregroundStyle(Palette.accent)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Palette.accent)
                    .scaleEffect(size / 20)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(String(localized: "Waiting to download"))
    }
}
