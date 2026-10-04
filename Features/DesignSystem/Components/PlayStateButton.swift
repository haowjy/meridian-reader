import SwiftUI

/// Where one thing on screen (a page, a book, a row) stands against what you hear.
enum PlayState: CaseIterable {
    /// Not what you hear. Tapping plays it, replacing what's playing.
    case idle
    /// Being made ready to play (extracting, fetching, the first audio).
    case preparing
    /// What you hear, playing. Tapping pauses.
    case playing
    /// What you hear, paused. Tapping resumes.
    case paused

    /// Whether this is what you hear.
    var isCurrent: Bool { self == .playing || self == .paused }

    var accessibilityLabel: String {
        switch self {
        case .idle: "Play"
        case .preparing: "Preparing"
        case .playing: "Pause"
        case .paused: "Resume"
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
struct PlayStateButton: View {
    enum Look: Equatable {
        case glyph
        /// `idleSymbol` shows while it isn't what you hear (`headphones` in the address field).
        case badge(idleSymbol: String)
        /// A labelled pill; the title says what it plays ("Listen · 9 min", "Playing · Ch 24").
        case pill(title: String, expands: Bool = false)
    }

    let state: PlayState
    var look: Look = .glyph
    let action: () -> Void

    var body: some View {
        switch look {
        case .glyph: glyph
        case .badge(let symbol): badge(symbol)
        case .pill(let title, let expands): pill(title, expands: expands)
        }
    }

    private var glyph: some View {
        Button(action: action) {
            Group {
                if state == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: state == .playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(state.isCurrent ? Palette.accent : Palette.ink)
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
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                case .preparing:
                    ProgressView().controlSize(.small)
                case .playing, .paused:
                    Circle().fill(Palette.accent)
                    PlayingBars(animating: state == .playing)
                        .foregroundStyle(Palette.onAccent)
                        .padding(Spacing.xs)
                }
            }
            .fieldControlFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .idle ? "Listen" : state.accessibilityLabel)
    }

    private func pill(_ title: String, expands: Bool) -> some View {
        PillButton(title: title, style: state.isCurrent ? .tinted : .filled, expands: expands, action: action) {
            switch state {
            case .idle:
                PillSymbol(name: "play.fill")
            case .preparing:
                ProgressView().controlSize(.small).tint(Palette.onAccent)
            case .playing, .paused:
                PlayingBars(animating: state == .playing)
                    .frame(width: Spacing.l, height: Spacing.l)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(state == .idle ? "" : state.accessibilityLabel)
    }
}

/// Four level bars: moving while something plays, still while it is paused. Still under Reduce
/// Motion. Takes the size it is offered and the foreground style around it.
struct PlayingBars: View {
    let animating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Heights of the still bars, as fractions of the frame.
    private static let rest: [CGFloat] = [0.35, 0.8, 0.5, 1]

    var body: some View {
        TimelineView(.animation(paused: !animating || reduceMotion)) { context in
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
        guard animating, !reduceMotion else { return Self.rest[i] }
        let speeds = [5.1, 6.7, 4.3, 5.9]
        return 0.3 + 0.7 * CGFloat(abs(sin(t * speeds[i] + Double(i))))
    }
}

#if DEBUG
struct PlayStateButtonGallery: View {
    var body: some View {
        PreviewGallery {
            ForEach(PlayState.allCases, id: \.self) { state in
                PreviewState("\(state)") {
                    HStack(spacing: Spacing.m) {
                        PlayStateButton(state: state) {}
                        PlayStateButton(state: state, look: .badge(idleSymbol: "headphones")) {}
                        PlayStateButton(state: state, look: .pill(title: Self.title(state))) {}
                    }
                }
            }
        }
    }

    private static func title(_ state: PlayState) -> String {
        state.isCurrent ? "Playing · Ch 24" : "Continue · Ch 24"
    }
}

#Preview("PlayStateButton · light", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.light) }
#Preview("PlayStateButton · dark", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.dark) }
#Preview("PlayStateButton · AX5", traits: .sizeThatFitsLayout) { PlayStateButtonGallery().previewVariant(.largestText) }
#endif
