import CoreGraphics

/// The spacing scale. Every padding, stack spacing and inset in feature code is one of these (or
/// a sum of them and a fixed glyph size); nothing in between.
///
/// ```
/// xxs 4 · xs 8 · s 12 · m 16 · l 20 · xl 24
/// page margin 20 (content edges) · band margin 12 (bottom chrome edges)
/// ```
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24

    /// Leading and trailing edge of page content: lists, headers, reading text.
    static let pageMargin: CGFloat = l
    /// Leading and trailing edge of the bottom chrome band (field capsule, toolbar, bars).
    static let bandMargin: CGFloat = s
}

/// Corner radii. Fields are drawn as true capsules (`Capsule()`, 44 pt tall at the default text
/// size), so they have no radius token; pills keep `pill` as they grow with Dynamic Type.
enum Radius {
    /// Cards, grouped lists, sheets, the Now Playing bar.
    static let card: CGFloat = 12
    /// Labelled pill buttons (48 pt tall at the default text size).
    static let pill: CGFloat = 24
}
