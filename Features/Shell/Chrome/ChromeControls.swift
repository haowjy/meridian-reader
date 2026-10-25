import SwiftUI

extension ChromeDestination {
    var symbol: String {
        switch self {
        case .reader: Icons.reader
        case .library: Icons.library
        case .browse: Icons.browser
        }
    }

    var label: String {
        switch self {
        case .reader: Verbs.reader
        case .library: Verbs.library
        case .browse: Verbs.browser
        }
    }

    var identifier: String {
        switch self {
        case .reader: "chromeReader"
        case .library: "chromeLibrary"
        case .browse: "chromeBrowser"
        }
    }

    var segment: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

extension View {
    /// The chrome's fixed-size glyphs don't grow with text; a long press shows this one large.
    func chromeLargeContent(_ label: String, symbol: String) -> some View {
        accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }
}

/// `[ Reader | Library | Browser ]`: three equal segments in one capsule, the lit one the screen
/// you are on, an inset capsule (equal padding, concentric corners). Every segment has the same icon
/// and label size and weight; lit differs by the glyph's tint and the capsule only (labels stay ink,
/// which holds 4.5:1 on the wash in every accent). The Reader segment shows what is playing: bars
/// while it plays, the plain document while paused, dimmed when there is nothing to open.
struct ChromePill: View {
    let lit: ChromeDestination
    /// The Reader segment's state; nil: nothing playing and nothing played to open.
    let reader: PlayState?
    let onSelect: (ChromeDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // The segments share the width left inside the inset, so the lit capsule is inset
            // equally on all four sides and its radius is the pill's minus the inset.
            let inset = ChromeMetrics.litInset
            let segment = (proxy.size.width - 2 * inset) / CGFloat(ChromeDestination.allCases.count)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.lit)
                    .frame(width: segment, height: proxy.size.height - 2 * inset)
                    .offset(x: segment * CGFloat(lit.segment) + inset)
                    .animation(reduceMotion ? nil : Motion.snappy, value: lit)
                HStack(spacing: 0) {
                    ForEach(ChromeDestination.allCases, id: \.self) { destination in
                        Button { onSelect(destination) } label: { content(destination) }
                            .buttonStyle(.plain)
                            .frame(width: segment)
                            .accessibilityLabel(destination.label)
                            .accessibilityIdentifier(destination.identifier)
                            .accessibilityAddTraits(destination == lit ? .isSelected : [])
                            .chromeLargeContent(destination.label, symbol: destination.symbol)
                    }
                }
                .padding(.horizontal, inset)
            }
        }
        .chromeSurface(Capsule())
    }

    @ViewBuilder
    private func content(_ destination: ChromeDestination) -> some View {
        let isLit = destination == lit
        let dimmed = destination == .reader && reader == nil && !isLit
        VStack(spacing: ChromeMetrics.segmentGap) {
            Group {
                if destination == .reader, reader == .playing {
                    Image(systemName: Icons.playing).symbolEffect(.variableColor.iterative, isActive: true)
                } else if destination == .reader, reader == .preparing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: destination.symbol)
                }
            }
            .font(.system(size: BottomChrome.iconSize, weight: .medium))
            .foregroundStyle(isLit || (destination == .reader && reader?.isCurrent == true) ? Palette.accent : Palette.ink)
            .frame(height: ChromeMetrics.segmentGlyphHeight)
            Text(destination.label)
                .font(.system(size: ChromeMetrics.labelSize, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .opacity(dimmed ? ChromeMetrics.segmentDimmedOpacity : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// The collapsed row's current-screen icon: the document, the books or the globe, plain. Tapping
/// it is swiping up: the pill comes back.
struct ChromeScreenIcon: View {
    let destination: ChromeDestination
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: destination.symbol)
                .font(.system(size: BottomChrome.iconSize, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .chromeSurface(Circle())
        .accessibilityLabel(destination.label)
        .accessibilityHint(String(localized: "Shows the bar"))
        .accessibilityIdentifier("chromeScreenIcon")
        .chromeLargeContent(destination.label, symbol: destination.symbol)
    }
}

/// ‹ and ›: one capsule, the buttons side by side in the frame the host gives it.
struct ChromeNavigation: View {
    let canGoBack: Bool
    let showsForward: Bool
    let backID: String
    let forwardID: String
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(Icons.back, label: Verbs.back, id: backID, enabled: canGoBack, action: onBack)
            if showsForward {
                button(Icons.forward, label: Verbs.forward, id: forwardID, enabled: true, action: onForward)
            }
        }
        .chromeSurface(Capsule())
    }

    private func button(_ symbol: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: BottomChrome.iconSize, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Palette.disabledOpacity)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .chromeLargeContent(label, symbol: symbol)
    }
}

/// ⋯'s button face in the chrome: the glyph on a round surface, the whole frame tappable.
struct ChromeRoundLabel: View {
    let symbol: String
    /// What the glyph is called, for the large content viewer.
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: BottomChrome.iconSize, weight: .medium))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .chromeSurface(Circle())
            .chromeLargeContent(label, symbol: symbol)
    }
}

/// The play / pause button beside the pill: a ring that fills as the page plays around ▶ or ⏸.
/// Its own view because the ring reads the live offset, which moves several times a second.
struct ChromePlayButton: View {
    let state: PlayState
    /// 0 to 1; read here, in this view's body, so only the button redraws as it moves.
    let progress: () -> Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Palette.track, lineWidth: ChromeMetrics.ringWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress())))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: ChromeMetrics.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if state == .preparing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state == .playing ? Icons.pause : Icons.play)
                        .font(.system(size: BottomChrome.iconSize, weight: .medium))
                        .foregroundStyle(state.isCurrent ? Palette.accent : Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(ChromeMetrics.ringInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .chromeSurface(Circle())
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityIdentifier("chromePlayPause")
        .chromeLargeContent(state.accessibilityLabel, symbol: state == .playing ? Icons.pause : Icons.play)
    }
}
