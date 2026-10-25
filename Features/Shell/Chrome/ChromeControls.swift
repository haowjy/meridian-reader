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

/// `[ Reader | Library | Browser ]`, and the screen icon it folds into: one capsule whose rect the
/// layout animates between the full pill and the icon's circle. Folding is the lit segment's glyph
/// sliding to the middle while the other segments, their labels and the lit wash fade, so the
/// lit segment is the icon. Every segment has the same icon and label size and weight; lit differs
/// by the glyph's tint and the wash only (labels stay ink, which holds 4.5:1 on the wash in every
/// accent). The Reader segment is the plain document whether or not anything plays (▶ and the lit
/// segment say what plays); it is dimmed when there is nothing to open and it is not lit.
///
/// Expanded, each segment is a button; folded (past half), the whole circle is one: a tap on the icon
/// is a swipe up.
struct ChromePill: View {
    let lit: ChromeDestination
    /// Something is playing or was played: the Reader segment has a page to open.
    let hasReader: Bool
    /// How far the pill has folded into the icon (`ChromeLayout.fold`).
    let fold: CGFloat
    /// The pill's width while expanded: the segments are laid out in it.
    let expandedWidth: CGFloat
    let onSelect: (ChromeDestination) -> Void
    let onExpand: () -> Void

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
                    .opacity(1 - ChromeMetrics.ramp(fold, 0...0.5))
                    .animation(reduceMotion ? nil : Motion.snappy, value: lit)
                ForEach(ChromeDestination.allCases, id: \.self) { destination in
                    let isLit = destination == lit
                    let center = (CGFloat(destination.segment) + 0.5) * slot
                    segment(destination, lit: isLit)
                        .position(x: isLit ? center + (size.width / 2 - center) * fold : center, y: top + K.segmentGlyphHeight / 2
                                  + (size.height / 2 - top - K.segmentGlyphHeight / 2) * (isLit ? fold : 0))
                        .opacity(isLit ? 1 : 1 - ChromeMetrics.ramp(fold, 0...0.5))
                    label(destination)
                        .position(x: center, y: top + K.segmentGlyphHeight + K.segmentGap + K.labelSize / 2)
                        .opacity(1 - ChromeMetrics.ramp(fold, 0...0.4))
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

    /// The touch layer: three segments while expanded, the icon once folded.
    @ViewBuilder
    private func controls(slot: CGFloat, size: CGSize) -> some View {
        if fold > 0.5 {
            Button(action: onExpand) { Color.clear.contentShape(Circle()) }
                .buttonStyle(.plain)
                .frame(width: size.width, height: size.height)
                .accessibilityLabel(lit.label)
                .accessibilityHint(String(localized: "Shows the bar"))
                .accessibilityIdentifier("chromeScreenIcon")
                .chromeLargeContent(lit.label, symbol: lit.symbol)
        } else {
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
}

/// The collapsed Reader's field: the page's title in a capsule, nothing else (▶ is the row's).
/// Tapping it is swiping up: the card comes back.
struct ChromeTitleChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "Shows the bar"))
        .accessibilityIdentifier("chromeTitleChip")
    }
}

/// ‹ and ›: one capsule of one circle per button, in the frame the host gives it. The frame
/// animates between one and two circles' width, so › fades as it narrows.
struct ChromeNavigation: View {
    let showsForward: Bool
    let backID: String
    let forwardID: String
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = ChromeMetrics.barHeight
            HStack(spacing: 0) {
                button(Icons.back, label: Verbs.back, id: backID, action: onBack)
                    .frame(width: side)
                if showsForward {
                    button(Icons.forward, label: Verbs.forward, id: forwardID, action: onForward)
                        .frame(width: side)
                        .opacity(min(1, max(0, (proxy.size.width - side) / side)))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
        .chromeSurface(Capsule())
    }

    private func button(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BottomChrome.chromeGlyph)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
