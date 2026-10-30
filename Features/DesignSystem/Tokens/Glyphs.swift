import SwiftUI

/// Control sizes at the default text size: every button face, disc, field and hit area is one of
/// these. Sizes, not spacing: changing the spacing scale never resizes them.
///
/// ```
/// small 36 · tap 44 · bar 48 · prominent 62
/// ```
enum Control {
    /// A small face: a round icon control, a field control (mic, the speed), a compact pill (a
    /// sheet's bar buttons), a folder header's side controls, the folded chrome's bubble.
    static let small: CGFloat = 36
    /// The tap floor: no hit area is smaller, whatever it looks like. A toolbar's row, a row's ▶
    /// and ⋯, Now Playing's transport disc, a player card tool.
    static let tap: CGFloat = 44
    /// A labelled pill, every piece of the compact chrome (Safari's address bar, measured on an
    /// iPhone 17 Pro, iOS 26), the ▶ floating over a page in full screen.
    static let bar: CGFloat = 48
    /// The prominent ▶: Listen's player card and a folder header.
    static let prominent: CGFloat = 62
    /// How far a control, the field capsule, a row's minimum or a symbol grows with Dynamic Type,
    /// as a multiple of its default size: enough that text and glyphs never clip, while the
    /// chrome stays a band.
    static let maxTextGrowth: CGFloat = 1.5

    /// A Dynamic Type–scaled size (`@ScaledMetric` of `base`), kept between `base` and
    /// `maxTextGrowth` times it.
    static func grown(_ scaled: CGFloat, from base: CGFloat) -> CGFloat {
        min(max(scaled, base), base * maxTextGrowth)
    }
}

/// Symbol sizes, and the fixed measures of small indicators.
///
/// ```
/// small 16 · regular 20 · large 26
/// ```
enum Glyph {
    /// A glyph in a small or tight place: a pill's leading symbol, the ▶ floating over a page,
    /// the playing bars in Listen's circle.
    static let small: CGFloat = 16
    /// Every other control and row symbol: the chrome's and a toolbar's glyphs, a round control's,
    /// a row's ▶ and ⋯, a `SymbolRow`'s symbol, a book chapter's empty mark, the playing bars in a
    /// pill, a Settings choice's ✓, a row's listening column (one width whether it holds a ring,
    /// the bars or nothing, so every row's ring lines up).
    static let regular: CGFloat = 20
    /// A prominent glyph: the ▶ on a prominent disc, the player card's ⏮ ⏭, a folder header's ⋯,
    /// an action tile's symbol.
    static let large: CGFloat = 26
    /// The square a symbol stands in beside a row's text: a `SymbolRow`'s leading column (a symbol
    /// or a small site tile, so every such row's text starts at one place; it grows with the text
    /// like the row), a voice model's download.
    static let slot: CGFloat = 24
    /// A listening ring in a row's trailing column, part-way or full (rings mean listening,
    /// nothing else); the playing bars there.
    static let ring: CGFloat = 12
    /// The stroke of a ring, a drop target's outline and a chosen swatch's ring.
    static let stroke: CGFloat = 2
    /// A Frequently Visited tile on the start page: a site's icon.
    static let siteTile: CGFloat = 60
}

/// The floating panels: the ⋯ panel and Aa.
enum Panel {
    /// One width for both, so they read as one kind of thing.
    static let width: CGFloat = 320
}

extension View {
    /// The shadow under things that float over the page: a book cover.
    func floatingShadow(opacity: Double = 0.14) -> some View {
        shadow(color: Palette.scrim.opacity(opacity), radius: 12, y: 4)
    }

    /// The floating shadow, darker, for controls over the reading text (the
    /// floating ▶ / ⏸): the text runs under them.
    func overTextShadow() -> some View {
        floatingShadow(opacity: 0.2)
    }

    /// A symbol at one of the `Glyph` sizes (`weight` its weight), growing with the text only up to
    /// `Control.maxTextGrowth`, so it stays inside its row's column or its pill at the largest sizes.
    func glyphSize(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledGlyph(base: size, weight: weight))
    }

    /// The small chevron after a label that goes somewhere (*Show All ›*, a menu row's ›).
    func disclosureSymbol() -> some View {
        font(.caption.weight(.semibold))
    }
}

private struct ScaledGlyph: ViewModifier {
    let base: CGFloat
    let weight: Font.Weight
    @ScaledMetric private var scaled: CGFloat

    init(base: CGFloat, weight: Font.Weight) {
        self.base = base
        self.weight = weight
        _scaled = ScaledMetric(wrappedValue: base, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: Control.grown(scaled, from: base), weight: weight))
    }
}
