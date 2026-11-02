import SwiftUI

/// Where one thing on screen (a page, a book, a row) stands against what you hear.
enum PlayState: CaseIterable {
    /// Not what you hear. Tapping plays it, replacing what's playing.
    case idle
    /// Being made ready to play (extracting, fetching, the first audio).
    case preparing
    /// What you hear, playing. Tapping pauses.
    case playing
    /// What you hear, paused. Tapping continues it.
    case paused
    /// What you hear, waiting for the on-device voice to load before its first audio; it starts
    /// by itself once loaded. Tapping holds it (pause).
    case preparingVoice

    /// Whether this is what you hear.
    var isCurrent: Bool { self == .playing || self == .paused || self == .preparingVoice }
    /// Drawn as a spinner.
    var isPreparing: Bool { self == .preparing || self == .preparingVoice }

    var accessibilityLabel: String {
        switch self {
        case .idle: Verbs.play
        case .preparing: String(localized: "Preparing")
        case .preparingVoice: String(localized: "Preparing the voice")
        case .playing: Verbs.pause
        case .paused: Verbs.continue
        }
    }
}

/// The one play button, drawn from a `PlayState`: 🎧 in the address field, a row's trailing ▶, the
/// Now Playing bar's ⏸, the player's and a folder header's disc.
///
/// | Look | idle | preparing, preparingVoice | playing | paused |
/// |---|---|---|---|---|
/// | `glyph` (rows, the bar) | ▶ | spinner | ⏸ accent | ▶ accent |
/// | `badge` (🎧) | grey symbol | spinner | accent disc, moving bars | accent disc, still bars |
/// | `disc` (Now Playing's transport, full screen, a folder header, Listen's player card) | ▶ on an accent disc | spinner on the disc | ⏸ on the disc | ▶ on the disc |
struct PlayStateButton: View {
    enum Look: Equatable {
        case glyph
        /// `idleSymbol` shows while it isn't what you hear (`headphones` in the address field).
        case badge(idleSymbol: String)
        /// A round accent disc `size` wide (a `Control` size), its glyph `glyph` (a `Glyph` size), in the
        /// colour that reads on the accent. Fixed, like the toolbar glyphs (the large content viewer
        /// shows it at large text sizes): Now Playing's centre slot (`Control.tap`), the ▶ floating over
        /// a page in full screen (`Control.bar`, `Glyph.small`), a folder header's and Listen's player
        /// card's (`Control.prominent`, `Glyph.large`).
        case disc(size: CGFloat = Control.tap, glyph: CGFloat = Glyph.regular)
    }

    let state: PlayState
    var look: Look = .glyph
    let action: () -> Void

    /// On the reading page every look takes the theme's colours (the Reader's Now Playing bar,
    /// Listen).
    @Environment(\.readingPalette) private var reading

    var body: some View {
        switch look {
        case .glyph: glyph
        case .badge(let symbol): badge(symbol)
        case .disc(let size, let glyph):
            PlayStateDisc(state: state, size: size, glyphSize: glyph, action: action)
        }
    }

    private var glyph: some View {
        Button(action: action) {
            Group {
                if state.isPreparing {
                    ProgressView().tint(reading?.accent ?? Palette.accent)
                } else {
                    Image(systemName: state == .playing ? Icons.pause : Icons.play)
                        .glyphSize(Glyph.regular)
                        .foregroundStyle(state.isCurrent ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: Control.tap, height: Control.tap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private func badge(_ idleSymbol: String) -> some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .idle:
                    Image(systemName: idleSymbol)
                        .foregroundStyle(reading?.secondaryInk ?? Palette.secondaryInk)
                case .preparing, .preparingVoice:
                    ProgressView().controlSize(.small)
                case .playing, .paused:
                    Circle().fill(reading?.accent ?? Palette.accent)
                    PlayingBars(animating: state == .playing)
                        .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
                        .padding(Spacing.xs)
                }
            }
            .fieldControlFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .idle ? Verbs.listen : state.accessibilityLabel)
    }

}

/// The `disc` looks: the accent of the palette it sits on (the reading page's on Now Playing), a glyph
/// in the colour that reads on it. Fixed size, like the toolbar glyphs; the large content viewer
/// names it at large text sizes.
private struct PlayStateDisc: View {
    let state: PlayState
    let size: CGFloat
    let glyphSize: CGFloat
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let glyph = reading?.onAccent ?? Palette.onAccent
        Button(action: action) {
            ZStack {
                Circle().fill(reading?.accent ?? Palette.accent)
                if state.isPreparing {
                    ProgressView().tint(glyph)
                } else {
                    Image(systemName: state == .playing ? Icons.pause : Icons.play)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(glyph)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .tapTarget(size)
        }
        .buttonStyle(PillPressStyle())
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: state == .playing ? Icons.pause : Icons.play)
            Text(state.accessibilityLabel)
        }
    }
}

/// Four level bars: moving while something plays, still while it is paused. Still under Reduce
/// Motion. Takes the size it is offered and the foreground style around it.
struct PlayingBars: View {
    let animating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playingBarsMove) private var barsMove

    /// Heights of the still bars, as fractions of the frame.
    private static let rest: [CGFloat] = [0.35, 0.8, 0.5, 1]

    var body: some View {
        TimelineView(.animation(paused: !animating || reduceMotion || !barsMove)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let bar = g.size.width / 7
                HStack(alignment: .center, spacing: bar) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .frame(width: bar, height: g.size.height * height(i, at: t))
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, at t: TimeInterval) -> CGFloat {
        guard animating, !reduceMotion, barsMove else { return Self.rest[i] }
        let speeds = [5.1, 6.7, 4.3, 5.9]
        return 0.3 + 0.7 * CGFloat(abs(sin(t * speeds[i] + Double(i))))
    }
}

extension EnvironmentValues {
    /// Whether `PlayingBars` move while something plays (off: they stay still, as under Reduce
    /// Motion). `-uiTesting` turns it off: an animation that never ends keeps the app from going idle.
    @Entry var playingBarsMove = true
}

#if DEBUG
struct PlayStateButtonGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach(PlayState.allCases, id: \.self) { state in
                PreviewState("\(state)") {
                    HStack(spacing: Spacing.m) {
                        PlayStateButton(state: state) {}
                        PlayStateButton(state: state, look: .badge(idleSymbol: Icons.listen)) {}
                    }
                    HStack(spacing: Spacing.m) {
                        PlayStateButton(state: state, look: .disc()) {}
                        PlayStateButton(state: state, look: .disc(size: Control.bar, glyph: Glyph.small)) {}
                    }
                    .onReadingPreview()
                }
            }
        }
    }
}

#Preview("PlayStateButton · light", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.light) }
#Preview("PlayStateButton · dark", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.dark) }
#Preview("PlayStateButton · AX5", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.largestText) }
#endif
