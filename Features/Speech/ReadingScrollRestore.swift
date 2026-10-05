import CoreGraphics

/// The Reader's scroll position handed to Now Playing (D2), as this page's scroll offset, waiting
/// for the page's layout.
///
/// At `didFinish` the scroll view often has no content size yet, and WebKit's first layout puts the
/// offset back to the top, so the offset is set once the layout can hold it. It belongs to one load
/// of the page (`generation`); a new load, a drag, a scrub or a follow drops it. It never waits for
/// ever: once layout has been still for a moment (`quiet`), or the wait runs out (`expired`), an
/// offset the page can't reach is clamped into its range and the restore finishes.
struct ReadingScrollRestore: Equatable {
    /// The scroll view's layout: content height, viewport height and the insets around the text.
    struct Layout: Equatable {
        var contentHeight: CGFloat
        var viewportHeight: CGFloat
        var insetTop: CGFloat = 0
        var insetBottom: CGFloat = 0

        /// The offsets the text can scroll to.
        var range: ClosedRange<CGFloat> {
            let top = -insetTop
            return top...max(top, contentHeight - viewportHeight + insetBottom)
        }

        /// Laid out: the page has a height and a viewport to show it in.
        var isLaidOut: Bool { contentHeight > 0 && viewportHeight > 0 }
    }

    enum Step: Equatable {
        case wait
        /// Set the offset; the restore is done.
        case scroll(to: CGFloat)
    }

    let offset: CGFloat
    /// The page load it belongs to.
    let generation: Int

    func step(in layout: Layout, quiet: Bool, expired: Bool) -> Step {
        guard layout.isLaidOut else { return expired ? .scroll(to: layout.range.lowerBound) : .wait }
        let range = layout.range
        if range.contains(offset) { return .scroll(to: offset) }
        guard quiet || expired else { return .wait }
        return .scroll(to: min(max(offset, range.lowerBound), range.upperBound))
    }
}
