import SwiftUI

/// The type scale: a UI sans for chrome and lists, a serif for reading. Sizes are at the default
/// Dynamic Type size and scale with it (each follows the system text style named in
/// `relativeTo`). Apply with `.typeStyle(_:)`.
///
/// | Style | Size | Default | Scales like |
/// |---|---|---|---|
/// | title | 27 | serif bold | `.title` |
/// | heading | 20 | sans bold | `.title3` |
/// | body | 19 | serif | `.body` |
/// | row | 16 | sans | `.callout` |
/// | caption | 13 | sans | `.footnote` |
enum TypeStyle: CaseIterable {
    /// A page's title in the Reader and Now Playing.
    case title
    /// Top-level headers on a screen without a title ("Recent Searches"); a book's title.
    case heading
    /// Reading text.
    case body
    /// Row titles, field text, menu rows, buttons.
    case row
    /// Secondary lines: source, time left, counts, notes.
    case caption

    var size: CGFloat {
        switch self {
        case .title: 27
        case .heading: 20
        case .body: 19
        case .row: 16
        case .caption: 13
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .title: .title
        case .heading: .title3
        case .body: .body
        case .row: .callout
        case .caption: .footnote
        }
    }

    var design: Font.Design {
        switch self {
        case .title, .body: .serif
        case .heading, .row, .caption: .default
        }
    }

    var weight: Font.Weight {
        switch self {
        case .title, .heading: .bold
        case .body, .row, .caption: .regular
        }
    }
}

extension View {
    /// Sets the font to `style` at the current Dynamic Type size. `weight` / `design` override the
    /// style's own (a semibold row title; a sans title on a Library screen).
    func typeStyle(_ style: TypeStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(TypeStyleModifier(style: style, weight: weight, design: design))
    }
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    let weight: Font.Weight?
    let design: Font.Design?
    @ScaledMetric private var size: CGFloat

    init(style: TypeStyle, weight: Font.Weight?, design: Font.Design?) {
        self.style = style
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight ?? style.weight, design: design ?? style.design))
    }
}
