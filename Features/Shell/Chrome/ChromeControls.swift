import SwiftUI

extension ChromeDestination {
    var symbol: String {
        switch self {
        case .reader: Icons.listen
        case .library: Icons.library
        case .browse: Icons.browser
        }
    }

    var label: String {
        switch self {
        case .reader: Verbs.listen
        case .library: Verbs.library
        case .browse: Verbs.browser
        }
    }

    var identifier: String {
        switch self {
        case .reader: "chromeListen"
        case .library: "chromeLibrary"
        case .browse: "chromeBrowser"
        }
    }

    var segment: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// `[ Listen | Library | Browser ]`: one capsule, each segment a button. Every segment has the same
/// icon and label size and weight; lit differs by the glyph's tint and the wash only (labels stay
/// ink, which holds 4.5:1 on the wash in every accent). The Listen segment (`.reader`, the
/// destination's internal name) is the headphones whether or not anything plays (▶ and the lit
/// segment say what plays); it is dimmed when there is nothing to open and it is not lit.
struct ChromePill: View {
    let lit: ChromeDestination
    /// Something is playing or was played: the Reader segment has a page to open.
    let hasReader: Bool
    /// The pill's width while expanded: the segments are laid out in it.
    let expandedWidth: CGFloat
    let onSelect: (ChromeDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias K = ChromeMetrics

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let slot = expandedWidth / CGFloat(ChromeDestination.allCases.count)
            let blockHeight = K.segmentGlyphHeight + K.segmentGap + K.labelSize
            let top = (size.height - blockHeight) / 2
            ZStack(alignment: .topLeading) {
                // The wash is inset equally on all four sides; its radius is the pill's minus the inset.
                Capsule()
                    .fill(Palette.lit)
                    .frame(width: slot - 2 * K.litInset, height: size.height - 2 * K.litInset)
                    .offset(x: slot * CGFloat(lit.segment) + K.litInset, y: K.litInset)
                    .animation(reduceMotion ? nil : Motion.snappy, value: lit)
                ForEach(ChromeDestination.allCases, id: \.self) { destination in
                    let isLit = destination == lit
                    let center = (CGFloat(destination.segment) + 0.5) * slot
                    segment(destination, lit: isLit)
                        .position(x: center, y: top + K.segmentGlyphHeight / 2)
                    label(destination)
                        .position(x: center, y: top + K.segmentGlyphHeight + K.segmentGap + K.labelSize / 2)
                }
                controls(slot: slot, size: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(Capsule())
        }
        .chromeSurface(Capsule())
    }

    private func segment(_ destination: ChromeDestination, lit isLit: Bool) -> some View {
        Image(systemName: destination.symbol)
            .font(BottomChrome.chromeGlyph)
            .foregroundStyle(isLit ? Palette.accent : Palette.ink)
            .frame(height: K.segmentGlyphHeight)
            .opacity(dimmed(destination) ? K.segmentDimmedOpacity : 1)
            .accessibilityHidden(true)
    }

    private func label(_ destination: ChromeDestination) -> some View {
        Text(destination.label)
            .font(.system(size: K.labelSize, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(dimmed(destination) ? K.segmentDimmedOpacity : 1)
            .accessibilityHidden(true)
    }

    private func dimmed(_ destination: ChromeDestination) -> Bool {
        destination == .reader && !hasReader && destination != lit
    }

    /// The touch layer: one button per segment.
    private func controls(slot: CGFloat, size: CGSize) -> some View {
        ForEach(ChromeDestination.allCases, id: \.self) { destination in
            Button { onSelect(destination) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: slot, height: size.height)
                .offset(x: slot * CGFloat(destination.segment))
                .accessibilityLabel(destination.label)
                .accessibilityIdentifier(destination.identifier)
                .accessibilityAddTraits(destination == lit ? .isSelected : [])
                .chromeLargeContent(destination.label, symbol: destination.symbol)
        }
    }
}

/// ‹ and ›: one capsule of one circle per button, in the frame the host gives it. The frame
/// animates between one and two circles' width, so › fades as it narrows. A button that can't act
/// stays, dimmed and out of the taps' way; one that isn't `shown` has no circle.
struct ChromeNavigation: View {
    let showsBack: Bool
    let showsForward: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let backID: String
    let forwardID: String
    let onBack: () -> Void
    let onForward: () -> Void

    /// How much of a disabled arrow's ink stays: dimmed, still plainly there.
    static let disabledOpacity: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            let side = ChromeMetrics.navSingleWidth
            HStack(spacing: 0) {
                if showsBack {
                    button(Icons.back, label: Verbs.back, id: backID, enabled: canGoBack, action: onBack)
                        .frame(width: side)
                }
                if showsForward {
                    button(Icons.forward, label: Verbs.forward, id: forwardID, enabled: canGoForward, action: onForward)
                        .frame(width: side)
                        .opacity(showsBack ? min(1, max(0, (proxy.size.width - side) / side)) : 1)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
        .chromeSurface(Capsule())
    }

    private func button(_ symbol: String, label: String, id: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BottomChrome.chromeGlyph)
                .foregroundStyle(Palette.ink)
                .opacity(enabled ? 1 : Self.disabledOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
            .font(BottomChrome.chromeGlyph)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .chromeSurface(Circle())
            .chromeLargeContent(label, symbol: symbol)
    }
}

/// Listen's ‹: a glass capsule floating at the top left, ‹ and the place it goes back to ("‹ reddit.com"),
/// the Library ‹'s height (48 pt). The name truncates so it never reaches the middle of the screen.
struct ListenBackButton: View {
    let place: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ChromeMetrics.unit) {
                // ‹ in a 30 pt slot `fieldEndInset` from the end: concentric with the capsule's end cap,
                // where the Library's round ‹ draws it.
                Image(systemName: Icons.back).font(BottomChrome.chromeGlyph)
                    .frame(width: Glyph.fieldLeading, height: Glyph.fieldLeading)
                Text(place).font(BottomChrome.originLabel).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(Palette.ink)
            .padding(.leading, BottomChrome.fieldEndInset)
            .padding(.trailing, Spacing.s + ChromeMetrics.unit)
            .frame(height: ChromeMetrics.barHeight)
            .frame(maxWidth: ChromeMetrics.listenBackMaxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
            .chromeSurface(Capsule())
            .chromeLargeContent(Verbs.back, symbol: Icons.back)
        }
        .buttonStyle(.plain)
        .padding(.leading, ChromeMetrics.margin)
        .padding(.top, ChromeMetrics.unit)
        .accessibilityLabel(Verbs.back)
        .accessibilityValue(place)
        .accessibilityIdentifier("listenBack")
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
                        .font(BottomChrome.chromeGlyph)
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
