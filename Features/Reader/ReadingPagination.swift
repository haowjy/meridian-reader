import CoreGraphics

/// The reading page broken into pages of whole lines (Pages mode, `HTMLReadingView+Pages.swift`).
///
/// The page's script measures its lines: the text's line boxes, with images, the title card's
/// slot and the heading as single boxes, merged where they overlap and sorted top to bottom
/// (document y). Pages are filled greedily: the first starts at the content's top, each later one
/// at a line's top; a line that doesn't fit wholly starts the next page; a box taller than a page
/// shows in page-tall slices, from the top of the page it lands on while that one is still empty
/// (the first page's 0), until its bottom fits on a page, which carries on from there.
struct ReadingPagination: Equatable {
    struct Line: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    struct Article: Equatable {
        /// Shown at the top of the reading area: its first line's top (0 for the first page).
        var top: CGFloat
        /// Its last whole line's bottom (where a slice of a box taller than a page ends).
        var bottom: CGFloat
        /// How far it shows above `top` and below `bottom`: into the gap to the lines of the pages
        /// around it, at most `margin` (room for the spoken paragraph's tint, which pads its box).
        var visibleTop: CGFloat
        var visibleBottom: CGFloat
    }

    let pages: [Article]

    /// `lines` sorted by top, not overlapping; `height` the reading area's.
    init(lines: [Line], pageHeight height: CGFloat, margin: CGFloat) {
        var spans: [(top: CGFloat, bottom: CGFloat)] = []
        // The page being filled: its top, and its last whole line's bottom once it has one.
        var top: CGFloat = 0
        var bottom: CGFloat?
        for line in lines {
            if line.bottom <= top + height {
                bottom = line.bottom
                continue
            }
            // The line starts the next page.
            var start = line.top
            if let last = bottom {
                spans.append((top, last))
            } else if line.bottom - line.top > height {
                start = top
            }
            while line.bottom > start + height {
                spans.append((start, start + height))
                start += height
            }
            (top, bottom) = (start, line.bottom)
        }
        if let bottom { spans.append((top, bottom)) }
        if spans.isEmpty { spans = [(0, height)] }
        pages = spans.indices.map { i in
            let (top, bottom) = spans[i]
            return Article(top: top, bottom: bottom,
                        visibleTop: i == 0 ? top : max(spans[i - 1].bottom, top - margin),
                        visibleBottom: i == spans.count - 1 ? bottom + margin : min(spans[i + 1].top, bottom + margin))
        }
    }

    /// The page holding document y `y`: the last one starting at or above it.
    func index(holding y: CGFloat) -> Int {
        pages.lastIndex { $0.top <= y + 0.5 } ?? 0
    }
}
