import SwiftUI

extension ChromeDestination {
    var symbol: String {
        switch self {
        case .library: Icons.library
        case .browse: Icons.browser
        case .settings: Icons.settings
        }
    }

    var label: String {
        switch self {
        case .library: Verbs.library
        case .browse: Verbs.browser
        case .settings: Verbs.settings
        }
    }

    var identifier: String {
        switch self {
        case .library: "chromeLibrary"
        case .browse: "chromeBrowser"
        case .settings: "chromeSettings"
        }
    }

    var segment: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// `[ 📚 Library | 🧭 Browser | ⚙︎ Settings ]`: one capsule of equal segments, each a button showing its
/// glyph over its name, centred, as a tab bar does (the glyph `Glyph.small`, the name in
/// `TypeStyle.caption` semibold). The names show only while all three fit whole, across their segments and
/// within the lit wash's height (`pillLitHeight`) (`EqualSegmentsLayout` under `ViewThatFits`); otherwise
/// every segment is its glyph alone at the chrome's glyph size, so the pill never wraps, clips or grows
/// (large text sizes, a small `Control.tabBar`), and VoiceOver and the large content viewer keep the
/// names. Every segment has the same glyph size and weight; lit differs by the tint and the wash only.
/// The pill is `Control.tabBar` tall; each segment is tapped `pillHitOutset` above and below the glass,
/// at least `Control.tap` tall.
///
/// ```
/// [ (  📚   ) |   🧭    |    ⚙︎     ]     the names fit
/// [ (Library) | Browser | Settings ]
/// [   (📚)    |   🧭    |    ⚙︎     ]     they don't: glyphs alone
/// ```
struct ChromePill: View {
    let lit: ChromeDestination
    let onSelect: (ChromeDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias K = ChromeMetrics

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let slot = size.width / CGFloat(ChromeDestination.allCases.count)
            ZStack(alignment: .topLeading) {
                // The wash is inset equally on all four sides; its radius is the pill's minus the inset.
                Capsule()
                    .fill(Palette.lit)
                    .frame(width: slot - 2 * Spacing.xxs, height: size.height - 2 * Spacing.xxs)
                    .offset(x: slot * CGFloat(lit.segment) + Spacing.xxs, y: Spacing.xxs)
                    .animation(reduceMotion ? nil : Motion.snappy, value: lit)
                ViewThatFits(in: [.horizontal, .vertical]) {
                    segments(worded: true)
                    segments(worded: false)
                }
                .frame(width: size.width, height: K.pillLitHeight)
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(Capsule())
            // Outside the clip, so the taps reach past the glass.
            .overlay(alignment: .topLeading) { controls(slot: slot, size: size) }
        }
        .chromeSurface(Capsule())
    }

    /// The three segments' faces, equal thirds; `worded` with their names.
    private func segments(worded: Bool) -> some View {
        EqualSegmentsLayout(spacing: 0) {
            ForEach(ChromeDestination.allCases, id: \.self) { destination in
                segment(destination, lit: destination == lit, worded: worded)
            }
        }
    }

    /// A segment's face, centred in its third: the glyph over the name, or the glyph alone. Its
    /// horizontal padding keeps the name clear of the lit wash's ends (inset `Spacing.xxs`) by `Spacing.xs`.
    private func segment(_ destination: ChromeDestination, lit isLit: Bool, worded: Bool) -> some View {
        VStack(spacing: 0) {
            Image(systemName: destination.symbol)
                .font(worded ? .system(size: Glyph.small, weight: .medium) : BottomChrome.chromeGlyph)
            if worded {
                Text(destination.label)
                    .typeStyle(.caption, weight: .semibold)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .foregroundStyle(isLit ? Palette.accent : Palette.ink)
        .padding(.horizontal, Spacing.s)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The touch layer: one button per segment, `pillHitOutset` past the glass above and below.
    private func controls(slot: CGFloat, size: CGSize) -> some View {
        ForEach(ChromeDestination.allCases, id: \.self) { destination in
            Button { onSelect(destination) } label: {
                Color.clear.contentShape(ChromeHitShape.segment)
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

/// ‹, › and ⌂: one capsule of one circle per button, in the frame the host gives it. The frame
/// animates between one, two and three circles' width, so a trailing circle fades as it narrows. A
/// button that can't act stays, dimmed and out of the taps' way; one that isn't `shown` has no circle.
/// Each is tapped `Control.tap` square: alone `hitOutset` round its circle, side by side outward from
/// the shared edges (`ChromeMetrics.navHitSides`).
struct ChromeNavigation: View {
    let showsBack: Bool
    let showsForward: Bool
    let showsHome: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let backID: String
    let forwardID: String
    let homeID: String
    let onBack: () -> Void
    let onForward: () -> Void
    let onHome: () -> Void

    /// How much of a disabled arrow's ink stays: dimmed, still plainly there.
    static let disabledOpacity: CGFloat = 0.35

    private struct NavButton: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let enabled: Bool
        let action: () -> Void
    }

    /// The circles that show, in order: ‹, ›, ⌂.
    private var circles: [NavButton] {
        var all: [NavButton] = []
        if showsBack { all.append(NavButton(id: backID, symbol: Icons.back, label: Verbs.back, enabled: canGoBack, action: onBack)) }
        if showsForward {
            all.append(NavButton(id: forwardID, symbol: Icons.forward, label: Verbs.forward, enabled: canGoForward, action: onForward))
        }
        if showsHome { all.append(NavButton(id: homeID, symbol: Icons.startPage, label: Verbs.startPage, enabled: true, action: onHome)) }
        return all
    }

    var body: some View {
        GeometryReader { proxy in
            let side = ChromeMetrics.navSingleWidth
            let circles = circles
            HStack(spacing: 0) {
                ForEach(Array(circles.enumerated()), id: \.element.id) { index, circle in
                    button(circle, index: index, of: circles.count)
                        .frame(width: side)
                        // A circle past the frame's edge (the capsule narrowing as it goes) fades as it is covered.
                        .opacity(index == 0 ? 1 : min(1, max(0, (proxy.size.width - CGFloat(index) * side) / side)))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .chromeSurface(Capsule())
    }

    private func button(_ circle: NavButton, index: Int, of count: Int) -> some View {
        let sides = ChromeMetrics.navHitSides(index: index, of: count)
        return Button(action: circle.action) {
            Image(systemName: circle.symbol)
                .font(BottomChrome.chromeGlyph)
                .foregroundStyle(Palette.ink)
                .opacity(circle.enabled ? 1 : Self.disabledOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(ChromeHitShape(leading: sides.leading, trailing: sides.trailing))
        }
        .buttonStyle(.plain)
        .disabled(!circle.enabled)
        .accessibilityLabel(circle.label)
        .accessibilityIdentifier(circle.id)
        .chromeLargeContent(circle.label, symbol: circle.symbol)
    }
}
