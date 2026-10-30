import SwiftUI

extension ChromeDestination {
    var symbol: String {
        switch self {
        case .library: Icons.library
        case .browse: Icons.browser
        }
    }

    var label: String {
        switch self {
        case .library: Verbs.library
        case .browse: Verbs.browser
        }
    }

    var identifier: String {
        switch self {
        case .library: "chromeLibrary"
        case .browse: "chromeBrowser"
        }
    }

    var segment: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// `[ 📚 | 🧭 ]`: one capsule, each segment a button showing its glyph only (Library and Browser are
/// their names for VoiceOver and the large content viewer). Every segment has the same glyph size
/// and weight; lit differs by the glyph's tint and the wash only. Each segment is tapped
/// `hitOutset` above and below the glass, `minTapTarget` tall.
struct ChromePill: View {
    let lit: ChromeDestination
    let onSelect: (ChromeDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias K = ChromeMetrics

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let slot = ChromeMetrics.segmentWidth
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
                        .position(x: center, y: size.height / 2)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(Capsule())
            // Outside the clip, so the taps reach past the glass.
            .overlay(alignment: .topLeading) { controls(slot: slot, size: size) }
        }
        .chromeSurface(Capsule())
    }

    private func segment(_ destination: ChromeDestination, lit isLit: Bool) -> some View {
        Image(systemName: destination.symbol)
            .font(BottomChrome.chromeGlyph)
            .foregroundStyle(isLit ? Palette.accent : Palette.ink)
            .frame(height: K.segmentGlyphHeight)
            .accessibilityHidden(true)
    }

    /// The touch layer: one button per segment, `hitOutset` past the glass above and below.
    private func controls(slot: CGFloat, size: CGSize) -> some View {
        ForEach(ChromeDestination.allCases, id: \.self) { destination in
            Button { onSelect(destination) } label: {
                Color.clear.contentShape(ChromeHitShape(sides: false))
            }
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
                .contentShape(ChromeHitShape(sides: false))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .chromeLargeContent(label, symbol: symbol)
    }
}
