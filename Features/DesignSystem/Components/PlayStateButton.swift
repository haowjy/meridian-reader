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

    /// Whether this is what you hear.
    var isCurrent: Bool { self == .playing || self == .paused }

    var accessibilityLabel: String {
        switch self {
        case .idle: "Play"
        case .preparing: "Preparing"
        case .playing: "Pause"
        case .paused: Verbs.continue
        }
    }
}

/// The one play button, drawn from a `PlayState`: 🎧 in the address field, Listen in the Reader,
/// a book's Continue, a row's trailing ▶, the Now Playing bar's ⏸.
///
/// | Look | idle | preparing | playing | paused |
/// |---|---|---|---|---|
/// | `glyph` (rows, the bar) | ▶ | spinner | ⏸ accent | ▶ accent |
/// | `badge` (🎧) | grey symbol | spinner | accent disc, moving bars | accent disc, still bars |
/// | `pill` (Listen, Continue) | filled ▶ title | filled spinner title | tinted moving bars | tinted still bars |
/// | `disc` (Now Playing's transport) | ▶ on an accent disc | spinner on the disc | ⏸ on the disc | ▶ on the disc |
/// | `floatingDisc` (full screen) | as `disc`, smaller | | | |
struct PlayStateButton: View {
    enum Look: Equatable {
        case glyph
        /// `idleSymbol` shows while it isn't what you hear (`headphones` in the address field).
        case badge(idleSymbol: String)
        /// A labelled pill; the title says what it plays ("Listen", "Playing"), the lighter
        /// detail after it how long or where ("9 min", "Ch 24"). `fit`: how much of that shows in an
        /// `ActionButtonRow` (`.icon`: the ▶, spinner or bars alone).
        case pill(title: String, detail: String? = nil, expands: Bool = false, fit: ActionLabelFit = .full)
        /// A round accent disc, `BottomChrome.transportDiscSize` wide, with a dark glyph on the
        /// player: Now Playing's centre slot.
        case disc
        /// `disc` at `BottomChrome.floatingDiscSize`: the play / pause floating over a reading
        /// sheet in full screen.
        case floatingDisc
    }

    let state: PlayState
    var look: Look = .glyph
    let action: () -> Void

    /// The `glyph` look's symbol: `.title3`'s size, growing with the text only up to
    /// `BottomChrome.maxTextGrowth` so it stays inside its 44 pt column.
    @ScaledMetric(relativeTo: .title3) private var scaledGlyph: CGFloat = PlayStateButton.glyphSize
    /// On the reading page every look takes the theme's colours (the Reader's Now Playing bar,
    /// Listen).
    @Environment(\.readingPalette) private var reading

    static let glyphSize: CGFloat = 20

    var body: some View {
        switch look {
        case .glyph: glyph
        case .badge(let symbol): badge(symbol)
        case .pill(let title, let detail, let expands, let fit): pill(title, detail: detail, expands: expands, fit: fit)
        case .disc:
            PlayStateDisc(state: state, size: BottomChrome.transportDiscSize, glyphSize: BottomChrome.transportDiscGlyph,
                          action: action)
        case .floatingDisc:
            PlayStateDisc(state: state, size: BottomChrome.floatingDiscSize, glyphSize: BottomChrome.floatingDiscGlyph,
                          action: action)
        }
    }

    private var glyph: some View {
        Button(action: action) {
            Group {
                if state == .preparing {
                    ProgressView().tint(reading?.accent ?? Palette.accent)
                } else {
                    Image(systemName: state == .playing ? Icons.pause : Icons.play)
                        .font(.system(size: BottomChrome.grown(scaledGlyph, from: Self.glyphSize)))
                        .foregroundStyle(state.isCurrent ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
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
                case .preparing:
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
        .accessibilityLabel(state == .idle ? "Listen" : state.accessibilityLabel)
    }

    private func pill(_ title: String, detail: String?, expands: Bool, fit: ActionLabelFit) -> some View {
        PillButton(title: title, detail: detail, style: state.isCurrent ? .tinted : .filled, expands: expands,
                   fit: fit, action: action) {
            switch state {
            case .idle:
                PillSymbol(name: Icons.play)
            case .preparing:
                ProgressView().controlSize(.small).tint(reading?.onAccent ?? Palette.onAccent)
            case .playing, .paused:
                PlayingBars(animating: state == .playing)
                    .frame(width: Glyph.mark, height: Glyph.mark)
            }
        }
        .accessibilityLabel(PillButton<EmptyView>.accessibilityLabel(title: title, detail: detail))
        .accessibilityValue(state == .idle ? "" : state.accessibilityLabel)
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
                if state == .preparing {
                    ProgressView().tint(glyph)
                } else {
                    Image(systemName: state == .playing ? Icons.pause : Icons.play)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(glyph)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
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
    /// Motion). UI tests turn it off: an animation that never ends keeps the app from going idle.
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
                        PlayStateButton(state: state, look: .pill(title: Self.title(state), detail: "Ch 24")) {}
                    }
                    HStack(spacing: Spacing.m) {
                        PlayStateButton(state: state, look: .disc) {}
                        PlayStateButton(state: state, look: .floatingDisc) {}
                    }
                    .onReadingPreview()
                }
            }
        }
    }

    private static func title(_ state: PlayState) -> String {
        state.isCurrent ? "Playing" : Verbs.continue
    }
}

#Preview("PlayStateButton · light", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.light) }
#Preview("PlayStateButton · dark", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.dark) }
#Preview("PlayStateButton · AX5", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.largestText) }
#endif
