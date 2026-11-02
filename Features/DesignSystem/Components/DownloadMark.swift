import SwiftUI

/// Where a download, a fetch or a prepare stands, drawn one way app-wide, as the App Store draws
/// an app's download: a glyph before it starts, a thin accent arc spinning while it waits or starts
/// (no fraction yet), a thin accent ring filling clockwise once there is one (round a small ■
/// where a tap stops it), the same ring grey and still while paused, and the done glyph (or
/// nothing) after.
///
/// | idle | waiting | progress(0.4) | paused(0.4) | done |
/// |---|---|---|---|---|
/// | ⤓ (a voice) / ◯↓ (a prepare) | ◜ spinning (⌛ with Reduce Motion) | ◔ (■ when it stops) | ◔ grey | ✓ (a voice) / ●↓ (a prepare) |
///
/// A voice model's row and its closed section, a followed story's chapter rows, its header and
/// the Following sheet, a page's or folder's prepare (its row, its header's Prepare control, the
/// Prepared Audio list). Only draws; the caller makes it a button and says it to VoiceOver.
struct DownloadMark: View {
    enum State: Equatable {
        /// Not downloaded (not prepared): `act`'s glyph.
        case idle
        /// In the queue, starting, or under way with no size known: the spinning arc.
        case waiting
        /// Under way, 0…1 done: the ring filling.
        case progress(Double)
        /// Stopped part-way, to go on later: the ring, grey and still.
        case paused(Double)
        /// On the device (prepared): `act`'s done glyph.
        case done
    }

    /// What is coming: its glyphs before and after.
    enum Act {
        /// From the network (a voice model, a chapter's text): ⤓, then ✓.
        case download
        /// Rendered on the device (prepared audio): ◯↓, then ●↓ (✓ means selection).
        case prepare

        var idleSymbol: String { self == .download ? Icons.download : Icons.prepare }
        var doneSymbol: String { self == .download ? Icons.checkmark : Icons.prepared }
    }

    let state: State
    var act: Act = .download
    var size: CGFloat = Glyph.slot
    /// A tap stops it: the ring holds a small ■.
    var stops = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var turned = false

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                symbol(act.idleSymbol, tint: Palette.accent)
            case .waiting:
                if reduceMotion {
                    symbol(Icons.waiting, tint: Palette.accent)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.8)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                        .rotationEffect(.degrees(turned ? 360 : 0))
                        .onAppear { withAnimation(Motion.spin) { turned = true } }
                        .onDisappear { turned = false }
                }
            case .progress(let fraction), .paused(let fraction):
                let tint = state.isPaused ? Palette.secondaryInk : Palette.accent
                Circle().stroke(Palette.track, lineWidth: Glyph.stroke)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: Glyph.stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if stops {
                    Image(systemName: Icons.stop)
                        .font(.system(size: size * 0.33))
                        .foregroundStyle(tint)
                }
            case .done:
                symbol(act.doneSymbol, tint: Palette.accent, weight: .semibold)
            }
        }
        // The ring's stroke sits inside the frame, so every state takes the same square.
        .padding(Glyph.stroke / 2)
        .frame(width: size, height: size)
        .animation(Motion.standard, value: state)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, tint: Color, weight: Font.Weight = .regular) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .fontWeight(weight)
            .foregroundStyle(tint)
    }
}

extension DownloadMark.State {
    var isPaused: Bool { if case .paused = self { true } else { false } }
}

#if DEBUG
struct DownloadMarkGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("a download: not downloaded, starting, 40% (■ stops it), done") {
                HStack(spacing: Spacing.m) {
                    DownloadMark(state: .idle)
                    DownloadMark(state: .waiting)
                    DownloadMark(state: .progress(0.4), stops: true)
                    DownloadMark(state: .done)
                }
            }
            PreviewState("a prepare: not prepared, waiting its turn, 40%, paused at 60%, prepared") {
                HStack(spacing: Spacing.m) {
                    DownloadMark(state: .idle, act: .prepare)
                    DownloadMark(state: .waiting, act: .prepare)
                    DownloadMark(state: .progress(0.4), act: .prepare)
                    DownloadMark(state: .paused(0.6), act: .prepare)
                    DownloadMark(state: .done, act: .prepare)
                }
            }
            PreviewState("a folder header's control and a row's line two") {
                HStack(spacing: Spacing.m) {
                    DownloadMark(state: .progress(0.7), act: .prepare, size: Control.small, stops: true)
                    DownloadMark(state: .progress(0.7), act: .prepare, size: Glyph.inline)
                    DownloadMark(state: .waiting, size: Glyph.inline)
                }
            }
        }
    }
}

#Preview("DownloadMark · light", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.light) }
#Preview("DownloadMark · dark", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.dark) }
#Preview("DownloadMark · AX5", traits: .sizeThatFitsLayout) { DownloadMarkGallery().previewVariant(.largestText) }
#endif
