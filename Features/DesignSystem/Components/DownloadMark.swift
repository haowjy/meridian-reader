import SwiftUI

/// Where a page's or folder's download stands (`DownloadCenter.state(of:)`): what its row's mark,
/// its menu's *Download* / *Remove Download* and a folder header's Download control show.
enum DownloadState: Equatable {
    /// Not downloaded and not queued.
    case notDownloaded
    /// Queued or rendering: how much of it is ready, 0…1 (a folder's; a page's row shows only
    /// that it downloads, and its fraction stays 0).
    case downloading(fraction: Double)
    /// Queued, and its download paused: drawn as downloading, in grey, everywhere it shows (a
    /// row's tile, a folder header's control, the Downloads list).
    case paused(fraction: Double)
    /// Every page it covers is downloaded (in the download voice, or one its download kept).
    case downloaded

    /// Downloading or paused: it has pages still to download.
    var isDownloading: Bool {
        switch self {
        case .downloading, .paused: true
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
        case .paused: String(localized: "Paused")
        case .downloaded: String(localized: "Downloaded")
        }
    }

    /// "40 percent" while downloading; "" otherwise.
    var percentText: String {
        switch self {
        case .downloading(let fraction), .paused(let fraction):
            String(localized: "\(Int((fraction * 100).rounded())) percent")
        default: ""
        }
    }
}

/// Download progress, drawn one way app-wide (rings mean listening only): an outline ↓ before it
/// downloads, the circle filling with the accent from the bottom as it downloads (the ↓ turning
/// white where the fill has reached it), the same in grey while paused, a grey filled ✓ once
/// downloaded. A folder header's Download control, a download in the Downloads list, a voice
/// model in Settings. Only draws; the caller makes it a button.
///
/// | notDownloaded | downloading(0.4) | downloaded |
/// |---|---|---|
/// | ◯↓ secondary | ◯↓ 40% filled | ● ✓ secondary |
struct DownloadMark: View {
    let state: DownloadState
    var size: CGFloat = Glyph.control

    var body: some View {
        ZStack {
            switch state {
            case .notDownloaded:
                Circle().strokeBorder(Palette.secondaryInk, lineWidth: lineWidth)
                arrow.foregroundStyle(Palette.secondaryInk)
            case .downloading(let fraction), .paused(let fraction):
                let filled = size * min(max(fraction, 0), 1)
                let tint = state.isPaused ? Palette.secondaryInk : Palette.accent
                Circle().strokeBorder(tint, lineWidth: lineWidth)
                Circle().fill(tint).mask(alignment: .bottom) { Rectangle().frame(height: filled) }
                arrow.foregroundStyle(tint)
                arrow.foregroundStyle(Palette.onAccent).mask(alignment: .bottom) { Rectangle().frame(height: filled) }
            case .downloaded:
                Circle().fill(Palette.secondaryInk)
                Image(systemName: Icons.checkmark)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Palette.paper)
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
