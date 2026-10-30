import SwiftUI
import UIKit

/// The reading page's look in HTML (the Reader and Now Playing render articles in a web view):
/// the reading theme's tokens (`ReadingPalette`) written as CSS, the same page for both sheets.
/// Every paragraph is in full ink (C105); the spoken one sits on the highlight, and the spoken sentence is underlined in the theme's accent. The title and source line are part of the page.
///
/// Everything that can change while a page is up is a CSS variable: the type sizes (Dynamic
/// Type, `Sizes`) and the look (`Look`: colours, typeface, text size, line spacing), applied in
/// place by `variablesScript` without reloading the page.
enum ReadingStyle {
    /// The type sizes at the current Dynamic Type size.
    struct Sizes: Equatable {
        var body: CGFloat
        var title: CGFloat
        var caption: CGFloat
        /// The heading's Listen pill (`TypeStyle.row`, as `PillButton`'s title), grown no more than
        /// `Control.maxTextGrowth`.
        var row: CGFloat

        init(body: CGFloat, title: CGFloat, caption: CGFloat, row: CGFloat) {
            self.body = body
            self.title = title
            self.caption = caption
            self.row = row
        }

        /// Scaled like `typeStyle(_:)` for `traits` (nil: the current ones).
        init(traits: UITraitCollection? = nil) {
            func scaled(_ style: TypeStyle, _ text: UIFont.TextStyle) -> CGFloat {
                UIFontMetrics(forTextStyle: text).scaledValue(for: style.size, compatibleWith: traits)
            }
            self.init(body: scaled(.body, .body), title: scaled(.title, .title1), caption: scaled(.caption, .footnote),
                      row: Control.grown(scaled(.row, .callout), from: TypeStyle.row.size))
        }

        var cssVariables: String {
            "--body: \(Int(body.rounded()))px; --title: \(Int(title.rounded()))px; --caption: \(Int(caption.rounded()))px;"
                + " --row: \(Int(row.rounded()))px;"
        }
    }

    /// The reading appearance as the page draws it: the theme's colours resolved for one
    /// appearance, the typeface, the line spacing and the text size step's scale.
    struct Look: Equatable {
        var colors: Colors
        var font: ReadingFont = .serif
        var lineSpacing: ReadingLineSpacing = .normal
        /// The text size step (`ReadingTextSize`), on top of Dynamic Type.
        var textScale: Double = 1

        /// *Match App* in Jade, light, at the default type: what a page shows before it is told.
        static let standard = Look(colors: Colors(ReadingTheme.matchApp.palette(accent: .jade), scheme: .light))

        /// A body text line's height on the page at `sizes`.
        func lineHeight(_ sizes: Sizes) -> CGFloat {
            sizes.body.rounded() * textScale * lineSpacing.multiple
        }

        var cssVariables: String {
            colors.cssVariables + " --font: \(font.cssFamily); --leading: \(lineSpacing.multiple);"
                + " --scale: \(String(format: "%.2f", textScale));"
        }
    }

    /// A `ReadingPalette` as CSS colours, resolved for `scheme` (*Match App* follows the app's
    /// appearance; the other themes have one value).
    struct Colors: Equatable {
        var scheme: ColorScheme
        var paper: String
        var ink: String
        var dim: String
        var secondary: String
        var tertiary: String
        var accent: String
        var onAccent: String
        var highlight: String
        var underline: String
        var rule: String

        init(_ palette: ReadingPalette, scheme: ColorScheme) {
            let shown = palette.colorScheme ?? scheme
            let traits = UITraitCollection(userInterfaceStyle: shown == .dark ? .dark : .light)
            self.scheme = shown
            paper = ReadingStyle.hex(palette.background, traits)
            ink = ReadingStyle.hex(palette.ink, traits)
            dim = ReadingStyle.hex(palette.dimInk, traits)
            secondary = ReadingStyle.hex(palette.secondaryInk, traits)
            tertiary = ReadingStyle.hex(palette.tertiaryInk, traits)
            accent = ReadingStyle.hex(palette.accent, traits)
            onAccent = ReadingStyle.hex(palette.onAccent, traits)
            highlight = ReadingStyle.hex(palette.highlight, traits)
            underline = ReadingStyle.hex(palette.underline, traits)
            rule = ReadingStyle.hex(palette.track, traits)
        }

        var cssVariables: String {
            "color-scheme: \(scheme == .dark ? "dark" : "light"); --paper: \(paper); --ink: \(ink); --dim: \(dim);"
                + " --secondary: \(secondary); --tertiary: \(tertiary); --accent: \(accent);"
                + " --on-accent: \(onAccent); --highlight: \(highlight); --underline: \(underline); --rule: \(rule);"
        }
    }

    /// JavaScript that applies `sizes` and `look` to a loaded page.
    static func variablesScript(_ sizes: Sizes, _ look: Look) -> String {
        let style = (sizes.cssVariables + " " + look.cssVariables).replacingOccurrences(of: "'", with: "\\'")
        return "document.documentElement.setAttribute('style', '\(style)');"
    }

    /// The page's style sheet. `blockTags` are the listen blocks (paragraph spacing).
    static func css(sizes: Sizes, look: Look, blockTags: [String]) -> String {
        let blocks = blockTags.map { "\($0) { margin: 0 0 \(Int(Spacing.m))px; }" }.joined(separator: "\n")
        let margin = Int(Spacing.pageMargin)
        let pad = Int(Spacing.xs)
        return """
        :root { \(sizes.cssVariables) \(look.cssVariables) }
        html { -webkit-tap-highlight-color: transparent; background: var(--paper); }
        body { margin: 0; padding: \(pad)px \(margin)px calc(\(Int(Spacing.xl))px + var(--page-room, 0px));
               font-family: var(--font); font-size: calc(var(--body) * var(--scale)); line-height: var(--leading);
               -webkit-text-size-adjust: 100%; background: var(--paper); color: var(--ink); }
        a { color: var(--accent); }
        html.reader-paged { height: 100%; overflow-y: hidden; }
        html.reader-paged body { box-sizing: border-box; height: var(--page-h); padding-top: var(--page-top);
               padding-bottom: 0; column-width: calc(100vw - \(2 * margin)px); column-gap: \(2 * margin)px; column-fill: auto; }
        html.reader-paged img, html.reader-paged svg, html.reader-paged video, html.reader-paged iframe {
               max-height: calc(var(--page-h) - var(--page-top) - \(Int(Spacing.m))px); object-fit: contain;
               break-inside: avoid; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
        h1 { font-size: calc(var(--title) * var(--scale) * 0.9); }
        h2 { font-size: calc(var(--body) * var(--scale) * 1.2); }
        h3 { font-size: calc(var(--body) * var(--scale) * 1.08); }
        blockquote { padding-left: \(Int(Spacing.m))px; border-left: 2px solid var(--rule); }
        ul, ol { padding-left: 1.2em; }
        img, video, iframe { max-width: 100%; height: auto; }
        \(blocks)
        .reader-heading { margin: 0 0 \(Int(Spacing.xl))px; }
        .reader-title { font-size: calc(var(--title) * var(--scale)); font-weight: 700; line-height: 1.15;
                        margin: 0 0 \(pad)px; }
        /* One line: the site gives way first (an ellipsis), the length never wraps, ▶ Listen ends it. */
        .reader-detail { font-family: -apple-system, system-ui, sans-serif; font-size: var(--caption);
                         color: var(--tertiary); display: flex; align-items: center;
                         column-gap: calc(var(--caption) * \(Int(Spacing.s)) / \(Int(TypeStyle.caption.size))); }
        .reader-detail span { flex: 0 0 auto; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .reader-detail span:first-child { flex-shrink: 1; color: var(--secondary); }
        /* ▶ Listen: an accent capsule (`PillButton`'s compact filled pill: `Control.small` at the default size, growing
           with its text), at the line's end; its tap reaches \(Int(Control.tap)) pt tall. */
        .reader-listen { -webkit-appearance: none; appearance: none; border: 0; flex: none; margin-left: auto;
                         position: relative; box-sizing: border-box;
                         height: calc(var(--row) * \(Control.small / TypeStyle.row.size));
                         padding: 0 \(Int(Spacing.m))px; border-radius: 9999px;
                         background: var(--accent); color: var(--on-accent);
                         font-family: inherit; font-size: var(--row); font-weight: 600; line-height: 1; white-space: nowrap;
                         display: inline-flex; align-items: center; gap: \(Int(Spacing.xs))px; cursor: pointer; }
        /* Clear of Library Read's ⋯, which sits on the title's line at the top right. */
        .reader-detail:has(.reader-listen) { padding-top: \(Int(Spacing.xs))px; }
        .reader-listen::after { content: ""; position: absolute; left: 0; right: 0; top: 50%;
                         height: max(100%, \(Int(Control.tap))px); transform: translateY(-50%); }
        .reader-listen:active { opacity: \(Palette.pressedOpacity); }
        .reader-listen svg { width: 0.7em; height: 0.8em; fill: currentColor; }
        [data-reader-index] { border-radius: \(pad)px; transition: color \(Motion.standardResponse)s ease-out; }
        @media (prefers-reduced-motion: reduce) { [data-reader-index] { transition: none; } }
        html.reader-paged [data-reader-index] { transition: none; }
        /* Every paragraph stays in full ink (C105): only the spoken one gets the highlight. */
        body.reader-has-active .reader-active, .reader-active { color: var(--ink); background: var(--highlight);
                        box-shadow: 0 0 0 \(pad)px var(--highlight); }
        ::highlight(reader-sentence) { text-decoration: underline 2px var(--underline); text-underline-offset: 4px; }
        body.reader-jump [data-reader-index] {
          cursor: pointer;
          outline: 1px dashed color-mix(in srgb, var(--accent) 45%, transparent);
          outline-offset: 3px;
        }
        body.reader-jump [data-reader-index]:active {
          color: var(--ink);
          background: color-mix(in srgb, var(--accent) \(Int((Palette.washOpacity * 100).rounded()))%, transparent);
        }
        """
    }

    /// The article's HTML without stylesheets of its own (`<style>`, `<link rel="stylesheet">`):
    /// extracted pages carry the extractor's document styles (a sans `-apple-system-body`, a dark
    /// text colour, a `title1` heading), which would win over the reading style. Style blocks are
    /// never listen blocks, so paragraph numbering is unchanged.
    static func withoutPageStyles(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style\s*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<link\b[^>]*\brel\s*=\s*["']?stylesheet[^>]*>"#, with: "",
                                  options: .regularExpression)
    }

    static func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
