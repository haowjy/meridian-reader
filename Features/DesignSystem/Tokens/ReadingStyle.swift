import SwiftUI
import UIKit

/// The reading page's look in HTML (the Reader and Now Playing render articles in a web view):
/// the same tokens as SwiftUI, written as CSS. Paper and ink, the serif `body` and `title` sizes,
/// `caption` for the source line, the playing tint for the spoken paragraph and an accent
/// underline for the spoken sentence, each with its dark value.
///
/// Sizes are CSS variables (`--body`, `--title`, `--caption`), so a Dynamic Type change updates
/// them in place (`ReadingStyle.sizesScript`) without reloading the page.
enum ReadingStyle {
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
    static func css(sizes: Sizes, blockTags: [String]) -> String {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func vars(_ t: UITraitCollection) -> String {
            """
            --paper: \(hex(Palette.paper, t)); --ink: \(hex(Palette.ink, t));
            --secondary: \(hex(Palette.secondaryInk, t)); --accent: \(hex(Palette.accent, t));
            --tint: \(hex(Palette.playingTint, t));
            """
        }
        let blocks = blockTags.map { "\($0) { margin: 0 0 \(Int(Spacing.m))px; }" }.joined(separator: "\n")
        let margin = Int(Spacing.pageMargin)
        let tintPad = Int(Spacing.xs)
        return """
        :root { color-scheme: light dark; \(vars(light)) \(sizes.cssVariables) }
        @media (prefers-color-scheme: dark) { :root { \(vars(dark)) } }
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
                         color: var(--secondary); }
        [data-reader-index] { border-radius: \(Int(Spacing.xs))px; }
        .reader-active { background: var(--tint); box-shadow: 0 0 0 \(tintPad)px var(--tint); }
        ::highlight(reader-sentence) { text-decoration: underline 2px var(--accent); text-underline-offset: 4px; }
        body.reader-jump [data-reader-index] {
          cursor: pointer;
          outline: 1px dashed color-mix(in srgb, var(--accent) 45%, transparent);
          outline-offset: 3px;
        }
        body.reader-jump [data-reader-index]:active { background: color-mix(in srgb, var(--accent) 18%, transparent); }
        """
    }

    private static func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
