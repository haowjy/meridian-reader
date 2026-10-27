import SwiftUI

/// Fixed sizes of small glyphs and indicators. They are sizes, not spacing, so changing the
/// spacing scale never resizes them.
enum Glyph {
    /// A listening ring in a row's trailing column, part-way or full (rings mean listening,
    /// nothing else); the playing bars there.
    static let ring: CGFloat = 12
    /// A row's trailing listening column, just before its ⋯: one width whether it holds a ring,
    /// the bars or nothing, so every row's ring lines up (`ListRow`).
    static let listeningColumn: CGFloat = 20
    /// The stroke of a ring, a drop target's outline and a chosen swatch's ring.
    static let stroke: CGFloat = 2
    /// Playing bars beside a row's status; the empty slot beside the address field's text.
    static let indicator: CGFloat = 16
    /// A book preview's chapter row's empty leading mark (`ListRow`); the playing bars inside a
    /// play button; a Settings choice's ✓ or spinner.
    static let mark: CGFloat = 20
    /// A round control: a prepare's `PrepareMark` in the Prepared Audio list and a folder header, the
    /// header's ⋯.
    static let control: CGFloat = 28
    /// A voice model's download in Settings, beside its row's text.
    static let modelDownload: CGFloat = 24
    /// The leading slot of every band field (Library search and the browser's address): 🔍, or
    /// on a loaded page its 📄 / spinner, always this square so the text starts at one place.
    static let fieldLeading: CGFloat = 30
    /// The leading column of a `SymbolRow` (Settings, the ⋯ panel, the Move tree, search
    /// suggestions, Following's actions): one width for a symbol or a small site tile, so every
    /// such row's text starts at one place. It grows with the text like the row.
    static let rowLeading: CGFloat = 28
    /// A Favorites tile on the start page: a page's icon, a folder's square.
    static let favoriteTile: CGFloat = 60
    /// A book's cover inside its Favorites tile.
    static let favoriteCover: CGFloat = 30
}

/// The two minimum heights of a row at the default text size; larger text grows them up to
/// `BottomChrome.maxTextGrowth`.
enum RowHeight {
    /// A content row: a page, folder or book with its thumbnail and two lines (`ListRow`).
    static let content: CGFloat = 56
    /// A compact row: a symbol and a label, a setting, an action (`SymbolRow`).
    /// Matches the 44 pt tap floor (system Settings density); grows with Dynamic Type.
    static let compact: CGFloat = BottomChrome.minTapTarget
    /// A menu row in the ⋯ panel (a `SymbolRow`): the tap minimum, the height of a system menu's
    /// row, so an item's rows read alike in the panel and in its long press, and the longest
    /// panel (a folder's screen) fits an iPhone 17 Pro at the default text size.
    static let menu: CGFloat = BottomChrome.minTapTarget
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

    /// A symbol leading a compact row (`SymbolRow`, a search suggestion): body size, growing with
    /// the text like the row's column.
    func rowSymbol() -> some View {
        modifier(RowSymbol())
    }

    /// A symbol standing where a tile or a thumbnail would (a folder row's 📁, a Favorites folder
    /// tile's, a tile in the ⋯ panel, a voice's preview, Follow's checkboxes, the morph menu's glyphs): `.title3`.
    func tileSymbol() -> some View {
        font(.title3)
    }

    /// The small chevron after a label that goes somewhere (*Show All ›*, a menu row's ›).
    func disclosureSymbol() -> some View {
        font(.caption.weight(.semibold))
    }
}

/// Body size, growing with the text only up to `BottomChrome.maxTextGrowth`, so the symbol stays
/// inside its row's leading column at the largest sizes.
private struct RowSymbol: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = RowSymbol.base
    private static let base: CGFloat = 17

    func body(content: Content) -> some View {
        content.font(.system(size: BottomChrome.grown(size, from: Self.base)))
    }
}
