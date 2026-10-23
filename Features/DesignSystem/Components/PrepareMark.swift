import SwiftUI

/// Where a page's or folder's prepare stands (`PrepareCenter.state(of:)`): what its row's mark,
/// its menu's *Prepare* / *Remove Prepare* and a folder header's Prepare control show.
enum PrepareState: Equatable {
    /// Not prepared and not queued.
    case notPrepared
    /// Rendering now: how much of it is ready, 0…1 (a page's paragraphs rendered of its total; a
    /// folder's pages and the one rendering, `PrepareOverview.fraction`).
    case preparing(fraction: Double)
    /// Waiting its turn behind another prepare (not paused): how much of it is ready, 0…1. Drawn
    /// as a small spinner (an hourglass with Reduce Motion), never filling, so only what renders now fills (C90, C93).
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

    /// "40 percent" while preparing; "" otherwise.
    var percentText: String {
        switch self {
        case .preparing(let fraction), .queued(let fraction), .paused(let fraction):
            String(localized: "\(Int((fraction * 100).rounded())) percent")
        default: ""
        }
    }
}

/// Prepare progress, drawn one way app-wide (rings mean listening only): an outline ↓ before it
/// prepared audio, the circle filling with the accent from the top as it prepared audio (the ↓ turning
/// white where the fill has reached it), the same in grey while paused, a small spinner
/// while it waits its turn (C93: `QueuedIndicator`, a small spinner), a accent filled ↓ once prepared (C89: ✓ is selection's only). A
/// folder header's Prepare control, a row's tile while it prepared audio, a prepare in the
/// Downloads list, a voice model in Settings. Only draws; the caller makes it a button.
///
/// | notPrepared | queued | preparing(0.4) | prepared |
/// |---|---|---|---|
/// | ◯↓ secondary | spinner (⌛ Reduce Motion) | ◯↓ 40% filled | ● ↓ secondary |
struct PrepareMark: View {
    let state: PrepareState
    var size: CGFloat = Glyph.control

    var body: some View {
        ZStack {
            switch state {
            case .notPrepared:
                Circle().strokeBorder(Palette.secondaryInk, lineWidth: lineWidth)
                arrow.foregroundStyle(Palette.secondaryInk)
            case .queued:
                QueuedIndicator(size: size * 0.7)
            case .preparing(let fraction), .paused(let fraction):
                let filled = size * min(max(fraction, 0), 1)
                let tint = state.isPaused ? Palette.secondaryInk : Palette.accent
                Circle().strokeBorder(tint, lineWidth: lineWidth)
                Circle().fill(tint).mask(alignment: .top) { Rectangle().frame(height: filled) }
                arrow.foregroundStyle(tint)
                arrow.foregroundStyle(Palette.onAccent).mask(alignment: .top) { Rectangle().frame(height: filled) }
            case .prepared:
                Image(systemName: Icons.prepared)
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
        Image(systemName: Icons.prepareArrow)
            .font(.system(size: size * 0.5, weight: .bold))
    }
}

#if DEBUG
struct PrepareMarkGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("not downloaded, downloading 0%, 40%, 85%, downloaded") {
                HStack(spacing: Spacing.m) {
                    PrepareMark(state: .notPrepared)
                    PrepareMark(state: .preparing(fraction: 0))
                    PrepareMark(state: .preparing(fraction: 0.4))
                    PrepareMark(state: .preparing(fraction: 0.85))
                    PrepareMark(state: .queued(fraction: 0.3))
                    PrepareMark(state: .prepared)
                }
            }
            PreviewState("paused at 60%") {
                PrepareMark(state: .paused(fraction: 0.6))
            }
            PreviewState("small (a voice model in Settings)") {
                PrepareMark(state: .preparing(fraction: 0.3), size: 24)
            }
        }
    }
}

#Preview("DownloadMark · light", traits: .sizeThatFitsLayout) { PrepareMarkGallery().previewVariant(.light) }
#Preview("DownloadMark · dark", traits: .sizeThatFitsLayout) { PrepareMarkGallery().previewVariant(.dark) }
#Preview("DownloadMark · AX5", traits: .sizeThatFitsLayout) { PrepareMarkGallery().previewVariant(.largestText) }
#endif

/// Waiting its turn to prepare (C93), as music apps mark a queued track: a small activity
/// spinner in the accent (spokes, never a circle, so it can't read as a listening ring, which
/// lives in a row's right column), and a still accent hourglass when Reduce Motion is on. A
/// queued row's badge slot before its line two, a waiting prepare in the Prepared Audio list.
struct QueuedIndicator: View {
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: Icons.prepareQueued)
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
        .accessibilityLabel(String(localized: "Waiting to prepare"))
    }
}
