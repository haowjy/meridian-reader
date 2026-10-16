import SwiftUI

/// Where a page's or folder's download stands, as its Download button shows it.
enum DownloadState: Equatable {
    /// Not downloaded and not queued: tapping asks for it.
    case available
    /// Queued or rendering: how much of it is ready, 0…1.
    case downloading(fraction: Double)
    /// Every page it covers is downloaded (in the download voice, or one its download kept).
    case downloaded

    var accessibilityLabel: String {
        switch self {
        case .available: String(localized: "Download")
        case .downloading: String(localized: "Downloading")
        case .downloaded: String(localized: "Downloaded")
        }
    }
}

/// The one Download button, drawn from a `DownloadState`: ⬇ to ask for it, a ring filling while
/// it downloads, ✓ once it has. Only *available* takes a tap; the other two only report. The same
/// glyph beside a row's ▶ and in a folder header's row of pills, so Download reads one way on a
/// screen.
///
/// | available | downloading | downloaded |
/// |---|---|---|
/// | ⬇ accent | ring | ✓ secondary |
struct DownloadStateButton: View {
    let state: DownloadState
    let action: () -> Void

    @ScaledMetric(relativeTo: .title3) private var scaledGlyph: CGFloat = PlayStateButton.glyphSize

    var body: some View {
        Button(action: action) {
            mark
                .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                .contentShape(Circle())
                .tapTarget(BottomChrome.minTapTarget)
        }
        .buttonStyle(PillPressStyle())
        .disabled(state != .available)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: symbol ?? Icons.download)
            Text(state.accessibilityLabel)
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .downloading(let fraction):
            ProgressRing(fraction: fraction, size: Glyph.mark)
        case .available, .downloaded:
            // Matches its ▶ (`PlayStateButton`'s glyph).
            Image(systemName: symbol ?? Icons.download)
                .font(.system(size: BottomChrome.grown(scaledGlyph, from: PlayStateButton.glyphSize)))
                .foregroundStyle(state == .downloaded ? Palette.secondaryInk : Palette.accent)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var symbol: String? {
        switch state {
        case .available: Icons.download
        case .downloading: nil
        case .downloaded: Icons.downloaded
        }
    }

    private var accessibilityValue: String {
        guard case .downloading(let fraction) = state else { return "" }
        return "\(Int((fraction * 100).rounded())) percent"
    }
}

#if DEBUG
struct DownloadStateButtonGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach([DownloadState.available, .downloading(fraction: 0.4), .downloaded], id: \.accessibilityLabel) { state in
                PreviewState(state.accessibilityLabel) {
                    DownloadStateButton(state: state) {}
                }
            }
        }
    }
}

#Preview("DownloadStateButton · light", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.light) }
#Preview("DownloadStateButton · dark", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.dark) }
#Preview("DownloadStateButton · AX5", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.largestText) }
#endif
