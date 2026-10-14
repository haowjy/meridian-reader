import SwiftUI

/// Where a page's or folder's download stands, as its Download button shows it.
enum DownloadState: Equatable {
    /// Not downloaded and not queued: tapping asks for it.
    case available
    /// Queued or rendering: how much of it is ready, 0…1.
    case downloading(fraction: Double)
    /// Every page it covers is downloaded in the current voice.
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
/// it downloads, ✓ once it has. Only *available* takes a tap; the other two only report.
///
/// | Look | available | downloading | downloaded |
/// |---|---|---|---|
/// | `glyph` (a row, beside its ▶) | ⬇ accent | ring | ✓ secondary |
/// | `round` (a header's row of pills) | ⬇ on a chrome disc | ring on the disc | ✓ on the disc |
struct DownloadStateButton: View {
    enum Look {
        /// A 44 pt glyph, a row's trailing control.
        case glyph
        /// A round neutral button the height of a `PillButton`, in an `ActionButtonRow`.
        case round
    }

    let state: DownloadState
    var look: Look = .glyph
    let action: () -> Void

    @ScaledMetric(relativeTo: .callout) private var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .title3) private var scaledGlyph: CGFloat = PlayStateButton.glyphSize

    var body: some View {
        Button(action: action) {
            mark
                .frame(width: side, height: side)
                .background {
                    if look == .round { Circle().fill(Palette.chrome) }
                }
                .contentShape(Circle())
                .tapTarget(side)
        }
        .buttonStyle(PillPressStyle())
        .disabled(state != .available)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: symbol ?? "arrow.down.circle")
            Text(state.accessibilityLabel)
        }
    }

    /// A row's glyph keeps the tap target's size; the round look is a `PillButton`'s height and
    /// grows with it.
    private var side: CGFloat {
        switch look {
        case .glyph: BottomChrome.minTapTarget
        case .round: BottomChrome.grown(PillButton<EmptyView>.Size.regular.height * scale,
                                        from: PillButton<EmptyView>.Size.regular.height)
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .downloading(let fraction):
            ProgressRing(fraction: fraction, size: Glyph.mark)
        case .available, .downloaded:
            let image = Image(systemName: symbol ?? "arrow.down")
            Group {
                switch look {
                // A row's glyph matches its ▶ (`PlayStateButton`'s glyph).
                case .glyph: image.font(.system(size: BottomChrome.grown(scaledGlyph, from: PlayStateButton.glyphSize)))
                // The round one, a pill's symbol.
                case .round: image.typeStyle(.row, weight: .semibold)
                }
            }
            .foregroundStyle(state == .downloaded ? Palette.secondaryInk : look == .round ? Palette.ink : Palette.accent)
            .contentTransition(.symbolEffect(.replace))
        }
    }

    private var symbol: String? {
        switch state {
        case .available: look == .glyph ? "arrow.down.circle" : "arrow.down"
        case .downloading: nil
        case .downloaded: look == .glyph ? "checkmark.circle" : "checkmark"
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
                    HStack(spacing: Spacing.m) {
                        DownloadStateButton(state: state) {}
                        DownloadStateButton(state: state, look: .round) {}
                    }
                }
            }
        }
    }
}

#Preview("DownloadStateButton · light", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.light) }
#Preview("DownloadStateButton · dark", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.dark) }
#Preview("DownloadStateButton · AX5", traits: .sizeThatFitsLayout) { DownloadStateButtonGallery().previewVariant(.largestText) }
#endif
