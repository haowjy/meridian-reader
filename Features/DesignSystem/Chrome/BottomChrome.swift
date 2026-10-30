import SwiftUI

/// The sizes and helpers every bottom control shares, on both widths (docs/NAVIGATION.md): glyph
/// and tap-target sizes, the field capsule, the transport discs. The compact chrome's own sizes are
/// `ChromeMetrics`; the regular-width band's layout is in `RegularBand.swift`.
enum BottomChrome {
    /// Vertical padding inside the field capsule.
    static let fieldVerticalPadding = Spacing.xxs
    /// Field capsule / toolbar row height.
    static let rowHeight: CGFloat = 44
    /// The field capsule's fill: `chrome`, or the reading page's card.
    static func fieldFill(_ reading: ReadingPalette?) -> Color { reading?.card ?? Palette.chrome }
    /// Toolbar glyph size.
    static let iconSize: CGFloat = 19
    /// Every control glyph in the compact chrome, the field's controls too: one size, fixed, medium.
    static let chromeGlyph = Font.system(size: ChromeMetrics.segmentGlyphHeight, weight: .medium)
    /// The glyph inside a round icon control (`roundFieldControl`): the chrome glyph's weight (medium),
    /// scaled to the 36 pt circle. Fixed, like every chrome glyph.
    static let roundGlyph = Font.system(size: 18, weight: .medium)
    /// The address field's trailing 🎤 or ⊗ while searching: Safari's size and weight there.
    static let fieldAccessoryGlyph = Font.system(size: 17, weight: .regular)
    /// How far a 30 pt field glyph slot (🔍, 🎤, ⊗) sits in from the capsule's end while
    /// searching: equal top, bottom and end, so the slot is concentric with the end cap.
    static let fieldEndInset: CGFloat = (ChromeMetrics.barHeight - Glyph.fieldLeading) / 2
    /// Text on a round control's face (the speed): the same weight, even-width digits.
    static let roundText = Font.system(size: 15, weight: .medium).monospacedDigit()
    /// The place name on Listen's ‹ ("‹ reddit.com"): the chrome glyph's weight, fixed like it.
    static let originLabel = Font.system(size: 15, weight: .medium)
    /// Text standing in for a field control (the speed). Like the glyphs it keeps its size at
    /// large text sizes, so the controls never crowd.
    static let toolbarTextSize: CGFloat = 17
    /// Small controls inside the field capsule (mic, the speed) and in a sheet's top bar (☝︎).
    static let fieldControlSize: CGFloat = 36
    /// The smallest tap area of a control (`tapTarget`), whatever it looks like.
    static let minTapTarget = ChromeMetrics.minTapTarget
    /// Now Playing's round play / pause in the transport's centre slot. Fixed like the toolbar
    /// glyphs (the large content viewer shows it at large text sizes). The row stays
    /// `rowHeight`; the disc reaches past it above and below by half the difference.
    static let transportDiscSize: CGFloat = 52
    /// The glyph inside the transport disc.
    static let transportDiscGlyph: CGFloat = 21
    /// A folder header's play / pause between Prepare and More (C124): smaller than the
    /// transport's, its glyph in the same proportion.
    static let headerDiscSize: CGFloat = 56
    /// The glyph inside the header disc.
    static let headerDiscGlyph: CGFloat = (transportDiscGlyph * headerDiscSize / transportDiscSize).rounded()
    /// The play / pause disc floating over a reading page in full screen: one tap target wide.
    static let floatingDiscSize: CGFloat = minTapTarget
    /// The glyph inside the floating disc.
    static let floatingDiscGlyph: CGFloat = 18
    /// How far the field capsule and its controls grow with Dynamic Type, as a multiple of their
    /// default size: enough that text and glyphs never clip, while the chrome stays a band.
    static let maxTextGrowth: CGFloat = 1.5

    /// A Dynamic Type–scaled size (`@ScaledMetric` of `base`), kept between `base` and
    /// `maxTextGrowth` times it.
    static func grown(_ scaled: CGFloat, from base: CGFloat) -> CGFloat {
        min(max(scaled, base), base * maxTextGrowth)
    }
}

extension View {
    /// The field capsule: the browser's address field, the reader's scrub row and title row.
    /// 44 pt, growing with Dynamic Type (up to `maxTextGrowth`) so its text never clips.
    func bottomChromeField(leading: CGFloat = Spacing.s, trailing: CGFloat = Spacing.xxs) -> some View {
        modifier(BottomChromeField(leading: leading, trailing: trailing))
    }

    /// Toolbar icon: its cell of the toolbar row, 44 pt tall, full-cell tap target. The glyph
    /// keeps its size at large text sizes (like the system's toolbars); a long press shows it in
    /// the large content viewer instead.
    func toolbarIconFrame() -> some View {
        self.font(.system(size: BottomChrome.iconSize))
            .frame(maxWidth: .infinity, minHeight: BottomChrome.rowHeight)
            .contentShape(Rectangle())
            .accessibilityShowsLargeContentViewer()
    }

    /// A small control inside the field capsule (mic, Jump, bookmark): 36 pt with a body-size
    /// glyph, growing with Dynamic Type like the capsule; taps land anywhere in 44 pt. In the
    /// compact chrome's field: the chrome's fixed glyph in a 30 pt frame.
    func fieldControlFrame() -> some View {
        modifier(FieldControlFrame())
    }

    /// The app's one round icon control: 36 pt, `fill` with a hairline edge, the glyph at
    /// `BottomChrome.roundGlyph`, taps anywhere in 44 pt. Voice, the bookmark, Aa and ☝︎ on the
    /// player card and in a sheet's top bar, ✕ beside the search field. Use `RoundIconButton` for
    /// a plain symbol button.
    func roundFieldControl(fill: Color) -> some View {
        modifier(RoundFieldFace(fill: fill, isText: false))
    }

    /// The same face for a short text instead of a glyph (the playback speed): a circle, or a
    /// capsule as wide as the text needs.
    func roundFieldText(fill: Color) -> some View {
        modifier(RoundFieldFace(fill: fill, isText: true))
    }

    /// Text standing in for a field control (the speed in Now Playing's scrub capsule): as tall
    /// as one and at least as wide, wider for a longer label ("1.75×"), at the toolbar text's
    /// fixed size with even-width digits.
    func fieldTextFrame() -> some View {
        modifier(FieldTextFrame())
    }

    /// Grows the tap area of a control drawn `size` points wide to `BottomChrome.minTapTarget`
    /// without moving it or changing its look.
    func tapTarget(_ size: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -max(0, (BottomChrome.minTapTarget - size) / 2)))
    }
}

/// Fixed height (not minHeight): a Capsule with unbounded height becomes a circle when the layout
/// proposes a large vertical size (e.g. the idle address bar without the mic's frame).
private struct BottomChromeField: ViewModifier {
    let leading: CGFloat
    let trailing: CGFloat
    @ScaledMetric(relativeTo: .body) private var height = BottomChrome.rowHeight
    @Environment(\.readingPalette) private var reading
    @Environment(\.isChromeField) private var isChromeField

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, BottomChrome.fieldVerticalPadding)
            .frame(height: isChromeField ? ChromeMetrics.barHeight : BottomChrome.grown(height, from: BottomChrome.rowHeight))
            .chromeSurface(Capsule(), fill: BottomChrome.fieldFill(reading))
    }
}

private struct FieldControlFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = BottomChrome.fieldControlSize
    @Environment(\.isChromeField) private var isChromeField

    func body(content: Content) -> some View {
        if isChromeField {
            // In the compact chrome's fixed-height field: the chrome's glyph, in the field's slot.
            content
                .font(BottomChrome.chromeGlyph)
                .frame(width: Glyph.fieldLeading, height: Glyph.fieldLeading)
                .tapTarget(Glyph.fieldLeading)
                .accessibilityShowsLargeContentViewer()
        } else {
            let side = BottomChrome.grown(size, from: BottomChrome.fieldControlSize)
            content
                .font(.body)
                .frame(width: side, height: side)
                .tapTarget(side)
        }
    }
}

private struct RoundFieldFace: ViewModifier {
    let fill: Color
    let isText: Bool
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        let side = BottomChrome.fieldControlSize
        let edge = reading?.hairline ?? Palette.hairline
        content
            .font(isText ? BottomChrome.roundText : BottomChrome.roundGlyph)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, isText ? Spacing.xxs : 0)
            .frame(minWidth: isText ? BottomChrome.minTapTarget : side, minHeight: side, maxHeight: side)
            .background { Capsule().fill(fill) }
            .overlay { Capsule().strokeBorder(edge, lineWidth: 0.5) }
            .tapTarget(side)
            .accessibilityShowsLargeContentViewer()
    }
}

private struct FieldTextFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = BottomChrome.fieldControlSize

    func body(content: Content) -> some View {
        let side = BottomChrome.grown(size, from: BottomChrome.fieldControlSize)
        content
            .font(.system(size: BottomChrome.toolbarTextSize, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.xxs)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .contentShape(Rectangle())
            .tapTarget(side)
    }
}
