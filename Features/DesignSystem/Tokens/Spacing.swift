import CoreGraphics

/// The spacing scale. Every padding, stack spacing and inset in feature code is one of these (or
/// a sum of them and a fixed glyph size); nothing in between.
///
/// ```
/// xxs 4 · xs 8 · s 12 · m 16 · xl 24
/// page margin 20 (content edges) · band margin 12 (bottom chrome edges)
/// ```
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let xl: CGFloat = 24

    /// Leading and trailing edge of page content: lists, headers, reading text. An edge, not a
    /// sixth gap: nothing else is 20.
    static let pageMargin: CGFloat = 20
    /// Leading and trailing edge of the bottom chrome band (field capsule, toolbar, bars).
    static let bandMargin: CGFloat = s
    /// Leading and trailing edge of a top bar's buttons: where the system's navigation bar draws them
    /// (a book's or folder's `‹ … Edit ⋯`), and the in-place reading pages' top group, so the two line up.
    static let topBarMargin: CGFloat = m
}

/// Corner radii: two. Fields, pills and round controls are true capsules and circles (`Capsule()`,
/// `Circle()`), so they stay round as they grow with Dynamic Type and have no radius token.
enum Radius {
    /// Lists and small cards: grouped lists, sheets, the Now Playing bar, a search layer's card.
    static let card: CGFloat = 12
    /// A floating surface: Listen's player card, an action tile, a toast that wraps, the Aa panel's
    /// choices on more than one row.
    static let surface: CGFloat = 24
}
