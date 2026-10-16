import SwiftUI
import UIKit

/// The reading page's look in HTML (the Reader and Now Playing render articles in a web view):
/// the same tokens as SwiftUI, written as CSS, in one of two looks:
/// - `paper` (the Reader): paper and ink with their dark values, the serif `body` and `title`
///   sizes, `caption` for the source line, the playing tint for the spoken paragraph and an
///   accent underline for the spoken sentence.
/// - `player` (Now Playing), lyrics style on deep jade in both appearances: the spoken paragraph
///   in full `playerInk`, the others dimmed (`playerDimInk`), the sentence underlined in
///   `playerAccent`, no tint. Both looks underline the sentence in their accent. With nothing spoken (finished) every paragraph is full ink, as is a
///   paragraph pressed in jump mode (on the accent wash, dimmed ink would not read). The title
///   card is a native view over a slot at the top of the page (`.reader-top`).
///
/// Sizes are CSS variables (`--body`, `--title`, `--caption`), so a Dynamic Type change updates
/// them in place (`ReadingStyle.sizesScript`) without reloading the page.
enum ReadingStyle {
    enum Look: Equatable {
        case paper
        case player
    }

    /// The type sizes at the current Dynamic Type size.
    struct Sizes: Equatable {
        var body: CGFloat
        var title: CGFloat
        var caption: CGFloat

        init(body: CGFloat, title: CGFloat, caption: CGFloat) {
            self.body = body
            self.title = title
            self.caption = caption
        }

        /// Scaled like `typeStyle(_:)` for `traits` (nil: the current ones).
        init(traits: UITraitCollection? = nil) {
            func scaled(_ style: TypeStyle, _ text: UIFont.TextStyle) -> CGFloat {
                UIFontMetrics(forTextStyle: text).scaledValue(for: style.size, compatibleWith: traits)
            }
            self.init(body: scaled(.body, .body), title: scaled(.title, .title1), caption: scaled(.caption, .footnote))
        }

        var cssVariables: String {
            "--body: \(Int(body.rounded()))px; --title: \(Int(title.rounded()))px; --caption: \(Int(caption.rounded()))px;"
        }
    }

    /// JavaScript that applies `sizes` to a loaded page.
    static func sizesScript(_ sizes: Sizes) -> String {
        "document.documentElement.setAttribute('style', '\(sizes.cssVariables)');"
    }

    /// The page's style sheet. `blockTags` are the listen blocks (paragraph spacing).
    static func css(sizes: Sizes, blockTags: [String], look: Look = .paper) -> String {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func vars(_ t: UITraitCollection) -> String {
            """
            --paper: \(hex(Palette.paper, t)); --ink: \(hex(Palette.ink, t));
            --secondary: \(hex(Palette.secondaryInk, t)); --tertiary: \(hex(Palette.tertiaryInk, t));
            --accent: \(hex(Palette.accent, t));
            --tint: \(hex(Palette.playingTint, t));
            """
        }
        let scheme: String
        switch look {
        case .paper:
            scheme = """
            :root { color-scheme: light dark; \(vars(light)) \(sizes.cssVariables) }
            @media (prefers-color-scheme: dark) { :root { \(vars(dark)) } }
            .reader-active { background: var(--tint); box-shadow: 0 0 0 \(Int(Spacing.xs))px var(--tint); }
            """
        case .player:
            // One value in both appearances. The dimmed paragraphs fade in and out with the
            // spoken one (not under Reduce Motion).
            scheme = """
            :root { color-scheme: dark; --paper: \(hex(Palette.playerBackground, light));
                    --ink: \(hex(Palette.playerInk, light)); --dim: \(hex(Palette.playerDimInk, light));
                    --secondary: \(hex(Palette.playerSecondaryInk, light));
                    --tertiary: \(hex(Palette.playerTertiaryInk, light)); --accent: \(hex(Palette.playerAccent, light));
                    --tint: \(hex(Palette.playerTrack, light)); \(sizes.cssVariables) }
            body.reader-has-active { color: var(--dim); }
            body.reader-has-active .reader-active { color: var(--ink); }
            [data-reader-index] { transition: color \(Motion.standardResponse)s ease-out; }
            @media (prefers-reduced-motion: reduce) { [data-reader-index] { transition: none; } }
            body.reader-jump [data-reader-index]:active { color: var(--ink); }
            .reader-top { margin: 0 0 \(Int(Spacing.l))px; }
            """
        }
        let blocks = blockTags.map { "\($0) { margin: 0 0 \(Int(Spacing.m))px; }" }.joined(separator: "\n")
        let margin = Int(Spacing.pageMargin)
        return """
        \(scheme)
        html { -webkit-tap-highlight-color: transparent; background: var(--paper); }
        body { margin: 0; padding: \(Int(Spacing.xs))px \(margin)px \(Int(Spacing.xl))px;
               font-family: ui-serif, "New York", Georgia, serif; font-size: var(--body); line-height: 1.55;
               -webkit-text-size-adjust: 100%; background: var(--paper); color: var(--ink); }
        a { color: var(--accent); }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
        h1 { font-size: calc(var(--title) * 0.9); }
        h2 { font-size: calc(var(--body) * 1.2); }
        h3 { font-size: calc(var(--body) * 1.08); }
        blockquote { padding-left: \(Int(Spacing.m))px; border-left: 2px solid var(--tint); }
        ul, ol { padding-left: 1.2em; }
        img, video, iframe { max-width: 100%; height: auto; }
        \(blocks)
        .reader-heading { margin: 0 0 \(Int(Spacing.xl))px; }
        .reader-title { font-size: var(--title); font-weight: 700; line-height: 1.15; margin: 0 0 \(Int(Spacing.xs))px; }
        .reader-detail { font-family: -apple-system, system-ui, sans-serif; font-size: var(--caption);
                         color: var(--tertiary); display: flex; flex-wrap: wrap;
                         column-gap: calc(var(--caption) * \(Int(Spacing.s)) / \(Int(TypeStyle.caption.size))); }
        .reader-detail span { min-width: 0; overflow-wrap: anywhere; }
        .reader-detail span:first-child { color: var(--secondary); }
        [data-reader-index] { border-radius: \(Int(Spacing.xs))px; }
        ::highlight(reader-sentence) { text-decoration: underline 2px var(--accent); text-underline-offset: 4px; }
        body.reader-jump [data-reader-index] {
          cursor: pointer;
          outline: 1px dashed color-mix(in srgb, var(--accent) 45%, transparent);
          outline-offset: 3px;
        }
        body.reader-jump [data-reader-index]:active {
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

    private static func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
