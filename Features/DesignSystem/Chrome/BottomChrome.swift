import SwiftUI

/// The helpers every bottom control shares, on both widths (docs/NAVIGATION.md): the field capsule,
/// field controls, toolbar icons, tap targets. Their sizes are `Control` and `Glyph`; the compact
/// chrome's layout is `ChromeMetrics`; the regular-width band's layout is in `RegularBand.swift`.
enum BottomChrome {
    /// The field capsule's fill: `chrome`, or the reading page's card.
    static func fieldFill(_ reading: ReadingPalette?) -> Color { reading?.card ?? Palette.chrome }
    /// Every control glyph in the compact chrome, the field's controls and a round icon control too:
    /// one size, fixed, medium.
    static let chromeGlyph = Font.system(size: Glyph.regular, weight: .medium)
    /// The address field's trailing 🎤 or ⊗ while searching: Safari's size and weight there.
    static let fieldAccessoryGlyph = Font.system(size: 17, weight: .regular)
    /// Text standing in for a field control (the speed). Like the glyphs it keeps its size at
    /// large text sizes, so the controls never crowd.
    static let toolbarTextSize: CGFloat = 17
}

extension View {
    /// The field capsule: the browser's address field, the reader's scrub row and title row.
    /// 44 pt, growing with Dynamic Type (up to `Control.maxTextGrowth`) so its text never clips.
    func bottomChromeField(leading: CGFloat = Spacing.s, trailing: CGFloat = Spacing.xxs) -> some View {
        modifier(BottomChromeField(leading: leading, trailing: trailing))
    }

    /// Toolbar icon: its cell of the toolbar row, 44 pt tall, full-cell tap target. The glyph
    /// keeps its size at large text sizes (like the system's toolbars); a long press shows it in
    /// the large content viewer instead.
    func toolbarIconFrame() -> some View {
        self.font(.system(size: Glyph.regular))
            .frame(maxWidth: .infinity, minHeight: Control.tap)
            .contentShape(Rectangle())
            .accessibilityShowsLargeContentViewer()
    }

    /// A small control inside the field capsule (mic, Jump, bookmark): 36 pt with a body-size
    /// glyph, growing with Dynamic Type like the capsule; taps land anywhere in 44 pt. In the
    /// compact chrome's field: the chrome's fixed glyph in its 24 pt slot.
    func fieldControlFrame() -> some View {
        modifier(FieldControlFrame())
    }

    /// The app's one round icon control: 36 pt, `fill` with a hairline edge, the glyph at
    /// `BottomChrome.chromeGlyph`, taps anywhere in 44 pt. Voice, the bookmark, Aa and ☝︎ on the
    /// player card and in a sheet's top bar. `IconButton` and `SaveToggleButton` draw it (`iconButtonFace`).
    func roundFieldControl(fill: Color) -> some View {
        modifier(RoundFieldFace(fill: fill))
    }

    /// Text standing in for a field control (the speed in Now Playing's scrub capsule): as tall
    /// as one and at least as wide, wider for a longer label ("1.75×"), at the toolbar text's
    /// fixed size with even-width digits.
    func fieldTextFrame() -> some View {
        modifier(FieldTextFrame())
    }

    /// Grows the tap area of a control drawn `size` points wide to `Control.tap`
    /// without moving it or changing its look.
    func tapTarget(_ size: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -max(0, (Control.tap - size) / 2)))
    }
}

/// Fixed height (not minHeight): a Capsule with unbounded height becomes a circle when the layout
/// proposes a large vertical size (e.g. the idle address bar without the mic's frame).
private struct BottomChromeField: ViewModifier {
    let leading: CGFloat
    let trailing: CGFloat
    @ScaledMetric(relativeTo: .body) private var height = Control.tap
    @Environment(\.readingPalette) private var reading
    @Environment(\.isChromeField) private var isChromeField

    func body(content: Content) -> some View {
        content
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, Spacing.xxs)
            .frame(height: isChromeField ? Control.chrome : Control.grown(height, from: Control.tap))
            .chromeSurface(Capsule(), fill: BottomChrome.fieldFill(reading))
    }
}

private struct FieldControlFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = Control.small
    @Environment(\.isChromeField) private var isChromeField

    func body(content: Content) -> some View {
        if isChromeField {
            // In the compact chrome's fixed-height field: the chrome's glyph, in the field's slot.
            content
                .font(BottomChrome.chromeGlyph)
                .frame(width: ChromeMetrics.endGlyphSlot, height: ChromeMetrics.endGlyphSlot)
                .tapTarget(ChromeMetrics.endGlyphSlot)
                .accessibilityShowsLargeContentViewer()
        } else {
            let side = Control.grown(size, from: Control.small)
            content
                .font(.body)
                .frame(width: side, height: side)
                .tapTarget(side)
        }
    }
}

private struct RoundFieldFace: ViewModifier {
    let fill: Color
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        let side = Control.small
        let edge = reading?.hairline ?? Palette.hairline
        content
            .font(BottomChrome.chromeGlyph)
            .frame(width: side, height: side)
            .background { Circle().fill(fill) }
            .overlay { Circle().strokeBorder(edge, lineWidth: 0.5) }
            .tapTarget(side)
            .accessibilityShowsLargeContentViewer()
    }
}

private struct FieldTextFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = Control.small

    func body(content: Content) -> some View {
        let side = Control.grown(size, from: Control.small)
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
