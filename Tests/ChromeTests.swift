import XCTest
@testable import MeridianReader

/// The compact chrome's rules: its state (`ChromeState`), where every piece sits (`ChromeLayout`)
/// and how scrolling folds it (`ChromeScroll`). Pure values, no screen.
final class ChromeTests: XCTestCase {
    private typealias M = ChromeMetrics

    private func layout(_ destination: ChromeDestination, width: CGFloat = 393, progress: CGFloat = 0,
                        back: Bool = false, forward: Bool = false, keyboard: Bool = false) -> ChromeLayout {
        ChromeLayout(width: width, state: ChromeState(destination: destination, progress: progress,
                                                      canGoBack: back, canGoForward: forward, keyboard: keyboard))
    }

    // MARK: State

    func testEditHoldsTheChromeExpandedAndTheKeyboardHidesTheBubble() {
        var state = ChromeState(destination: .browse, progress: 1)
        XCTAssertEqual(state.collapse, 1)
        XCTAssertEqual(state.fold, 1)
        state = ChromeState(destination: .library, progress: 1, editing: true)
        XCTAssertEqual(state.collapse, 0)
        let typing = ChromeState(destination: .library, progress: 1, keyboard: true)
        XCTAssertEqual(typing.fold, 0, "no bubble while typing: the field's row is the only row")
    }

    func testEditKeepsBothRowsWhateverTheScroll() {
        let scrolled = ChromeLayout(width: 393, state: ChromeState(destination: .browse, progress: 1))
        let edit = ChromeLayout(width: 393, state: ChromeState(destination: .library, progress: 1, editing: true))
        XCTAssertTrue(scrolled.bubble.isShown)
        XCTAssertFalse(scrolled.pill.isShown, "scrolled: the rows are the bubble")
        XCTAssertFalse(edit.bubble.isShown, "Edit: row 2 stays")
        XCTAssertTrue(edit.editBar.isShown)
    }

    /// Listen is a chrome-sized disc ending row 1 on every destination, reader modes too, and the field
    /// gives it its room; typing and Edit have none, and the field runs to the margin.
    func testListenEndsRowOneOnEveryDestinationAndTheFieldYieldsToIt() {
        let width: CGFloat = 393
        for destination in ChromeDestination.allCases {
            for readerMode in [false, true] {
                let l = ChromeLayout(width: width, state: ChromeState(destination: destination, canGoBack: readerMode,
                                                                      readerMode: readerMode))
                let tag = "\(destination) reader mode \(readerMode)"
                XCTAssertTrue(l.listen.isShown, tag)
                XCTAssertEqual(l.listen.rect.width, Control.chrome, tag)
                XCTAssertEqual(l.listen.rect.height, Control.chrome, tag)
                XCTAssertEqual(l.listen.rect.maxX, width - Spacing.bandMargin, tag)
                XCTAssertEqual(l.listen.rect.minY, l.field.rect.minY, tag)
                XCTAssertEqual(l.field.rect.maxX + Spacing.xs, l.listen.rect.minX, tag)
            }
        }
        let typing = layout(.browse, width: width, keyboard: true)
        XCTAssertFalse(typing.listen.isShown, "typing: the field and Cancel only")
        let edit = ChromeLayout(width: width, state: ChromeState(destination: .library, editing: true))
        XCTAssertFalse(edit.listen.isShown, "Edit: the search alone on row 1")
        XCTAssertEqual(edit.field.rect.maxX, width - Spacing.bandMargin, "the field runs to the margin without Listen")
    }

    // MARK: Clearance

    /// What the chrome covers at each fold step, whatever the home indicator's strip: the rows end on it, and
    /// on a Home button phone `bubbleClearance` above the edge, as the bubble does.
    func testWhatTheChromeCoversAtEachStepEndsOnTheStrip() {
        let c = Control.chrome
        let steps = [0, 1, 2]
        let bubble = Spacing.xxs + Control.small + M.bubbleClearance
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 34) }, [M.rowsHeight, Spacing.xxs + c, bubble - 34], "above a 34 pt strip")
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 21) }, [M.rowsHeight, Spacing.xxs + c, bubble - 21],
                       "a 21 pt strip: the rows still end on it")
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 0) },
                       [M.rowsHeight + M.bubbleClearance, Spacing.xxs + c + M.bubbleClearance, bubble],
                       "a Home button phone: the rows end `bubbleClearance` above the edge, as the bubble does")
        XCTAssertEqual(M.keyboardClearance, Spacing.xxs + c, "the keyboard's row over the keyboard")
    }

    // MARK: Layout

    func testExpandedWidthsAtEveryPhone() {
        // Row 1 less the margins and Listen's disc and gap, less ‹ › and a gap with arrows.
        for width in [375.0, 393, 430] {
            let w = CGFloat(width)
            let none = w - 2 * Spacing.bandMargin - Control.chrome - Spacing.xs
            let both = none - M.navPairWidth - Spacing.xs
            let one = none - M.navSingleWidth - Spacing.xs
            XCTAssertEqual(layout(.browse, width: w, back: true, forward: true).field.rect.width, both)
            XCTAssertEqual(layout(.browse, width: w, back: true).field.rect.width, one, "‹ alone: nothing ahead")
            XCTAssertEqual(layout(.browse, width: w, forward: true).field.rect.width, both, "› works: the pair, ‹ dimmed")
            XCTAssertEqual(layout(.library, width: w, back: true).field.rect.width, none, "no arrows outside the Browser")
            XCTAssertEqual(layout(.browse, width: w).field.rect.width, one, "a new page keeps ‹, dimmed")
            XCTAssertEqual(layout(.library, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, w - 2 * Spacing.bandMargin, "the pill alone, margin to margin")
            XCTAssertEqual(layout(.settings, width: w).field.rect.width, none, "Search Settings as wide as Search Library")
            let segment = layout(.settings, width: w).pill.rect.width / CGFloat(ChromeDestination.allCases.count)
            XCTAssertGreaterThanOrEqual(segment, Control.tap, "each of the pill's equal segments is a tap target at \(w)")
        }
        XCTAssertEqual(ChromeDestination.allCases, [.library, .browse, .settings], "the pill's order")
    }

    /// Typing: the field and Cancel only (no pill, ⋯, Listen or arrows), margin to margin on every phone:
    /// the field from the left margin, Cancel (a word, `cancelWidth`) ending at the right margin, one gap
    /// between, at the bottom row's y, wherever the arrows were.
    func testTypingIsTheFieldAndCancelMarginToMargin() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                let l = layout(destination, width: width, back: true, forward: true, keyboard: true)
                let rest = layout(destination, width: width)
                let tag = "\(width) \(destination)"
                XCTAssertFalse(l.pill.isShown, tag)
                XCTAssertFalse(l.listen.isShown, tag)
                XCTAssertFalse(l.nav.isShown && l.navShowsBack, tag)
                XCTAssertTrue(l.field.isShown && l.cancel.isShown, tag)
                XCTAssertEqual(l.field.rect.minX, Spacing.bandMargin, "the field starts at the left margin: \(tag)")
                XCTAssertEqual(l.cancel.rect.maxX, width - Spacing.bandMargin, "Cancel ends at the right margin: \(tag)")
                XCTAssertEqual(l.cancel.rect.width, M.cancelWidth, tag)
                XCTAssertEqual(l.cancel.rect.height, Control.chrome, tag)
                XCTAssertEqual(l.cancel.rect.minX - l.field.rect.maxX, Spacing.xs, tag)
                XCTAssertEqual(l.field.rect.width, width - 2 * Spacing.bandMargin - Spacing.xs - M.cancelWidth, tag)
                // On the keyboard, not dipped into the home indicator's strip: the row ends at the box's bottom.
                XCTAssertEqual(l.field.rect.maxY, M.rowsHeight, "the row sits on the keyboard: \(tag)")
                XCTAssertEqual(l.cancel.rect.minY, l.field.rect.minY, tag)
                XCTAssertFalse(rest.cancel.isShown, "Cancel only while typing: \(tag)")
                XCTAssertLessThanOrEqual(l.field.rect.maxY, rest.pill.rect.maxY, "never below the resting row 2: \(tag)")
            }
        }
    }

    func testBrowseNeverHidesAnArrowThatWorks() {
        // Went back to the first page: › alone works. It shows in the pair, ‹ dimmed.
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let expanded = layout(.browse, width: width, forward: true)
            XCTAssertTrue(expanded.navShowsBack && expanded.navShowsForward, "the pair, ‹ dimmed, at \(width)")
            XCTAssertEqual(expanded.nav.rect.width, M.navPairWidth)
        }
        let fresh = layout(.browse)
        XCTAssertTrue(fresh.navShowsBack && !fresh.navShowsForward, "a new page: ‹ alone, dimmed")
        XCTAssertEqual(fresh.nav.rect.width, M.navSingleWidth)
    }

    /// One pill, one width, one x on every destination and state: tabs never move or resize it.
    func testThePillNeverMovesOrResizesAcrossDestinationsAndStates() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let reference = layout(.library, width: width)
            for destination in ChromeDestination.allCases {
                for back in [false, true] {
                    let l = layout(destination, width: width, back: back, forward: back)
                    XCTAssertEqual(l.pill.rect, reference.pill.rect, "\(destination) at \(width)")
                }
            }
        }
    }

    /// Both rows share the margins as their edges on every width (Jimmy: "the 2 bars should be the same
    /// length"): the pill alone runs margin to margin, as row 1 (the field, then Listen) does above it.
    func testBothRowsShareTheSameEdgesOnEveryWidth() {
        XCTAssertEqual(Spacing.bandMargin, 12)
        for width in [375.0, 393, 402, 430, 440, 744, 1024].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                let l = layout(destination, width: width)
                let tag = "\(destination) at \(width)"
                XCTAssertEqual(l.pill.rect.minX, Spacing.bandMargin, tag)
                XCTAssertEqual(l.pill.rect.maxX, width - Spacing.bandMargin, tag)
                let rowStart = l.nav.isShown ? l.nav.rect.minX : l.field.rect.minX
                XCTAssertEqual(rowStart, l.pill.rect.minX, "row 1 starts where row 2 does, \(tag)")
                XCTAssertEqual(l.listen.rect.maxX, l.pill.rect.maxX, "row 1 ends where row 2 does, \(tag)")
                XCTAssertFalse(l.cancel.isShown, "no ⋯ and no Cancel at rest, \(tag)")
            }
        }
    }

    func testEveryPieceIsAsTallAsItsTokenAndInsideTheMargins() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for (progress, keyboard) in [(0.0, false), (1.0, false), (0.0, true)] {
                    let l = layout(destination, width: width, progress: CGFloat(progress), back: true, forward: true, keyboard: keyboard)
                    let tag = "\(width) \(destination) progress \(progress) keyboard \(keyboard)"
                    let shown = [l.pill, l.field, l.nav, l.listen, l.cancel].filter(\.isShown)
                    for piece in shown {
                        let height = piece == l.pill ? Control.tabBar : Control.chrome
                        XCTAssertEqual(piece.rect.height, height, tag)
                        XCTAssertGreaterThanOrEqual(piece.rect.minX, Spacing.bandMargin - 0.01, tag)
                        XCTAssertLessThanOrEqual(piece.rect.maxX, width - Spacing.bandMargin + 0.01, tag)
                    }
                    for (i, a) in shown.enumerated() {
                        for b in shown[(i + 1)...] where abs(a.rect.minY - b.rect.minY) < Control.chrome / 2 {
                            let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
                            XCTAssertGreaterThanOrEqual(gap, Spacing.xs - 0.01, tag)
                        }
                    }
                }
            }
        }
    }

    /// Each control's own hit area, from the shape its view draws (`ChromeHitShape` and its sides), not the
    /// piece it sits in: ‹ and › each (alone and paired), the field, the lit reader icon at the field's end,
    /// Listen, Cancel and the pill's segments. Every one is at least `Control.tap` square and no two overlap (but the
    /// reader icon, which is the field's own).
    func testEveryControlIsTapped44AndNoTwoHitAreasOverlap() {
        func hit(_ rect: CGRect, _ shape: ChromeHitShape = ChromeHitShape()) -> CGRect { shape.path(in: rect).boundingRect }
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for forward in [false, true] {
                    for keyboard in [false, true] {
                        let l = layout(destination, width: width, back: true, forward: forward, keyboard: keyboard)
                        let tag = "\(width) \(destination) forward \(forward) keyboard \(keyboard)"
                        var hits: [(String, CGRect)] = []
                        if l.nav.isShown {
                            let side = M.navSingleWidth, paired = l.navShowsBack && l.navShowsForward
                            if l.navShowsBack {
                                let s = M.arrowHitSides(paired: paired, isBack: true)
                                hits.append(("‹", hit(CGRect(x: l.nav.rect.minX, y: l.nav.rect.minY, width: side, height: side),
                                                      ChromeHitShape(leading: s.leading, trailing: s.trailing))))
                            }
                            if l.navShowsForward {
                                let s = M.arrowHitSides(paired: paired, isBack: false)
                                let x = l.nav.rect.minX + (l.navShowsBack ? side : 0)
                                hits.append(("›", hit(CGRect(x: x, y: l.nav.rect.minY, width: side, height: side),
                                                      ChromeHitShape(leading: s.leading, trailing: s.trailing))))
                            }
                        }
                        if l.field.isShown { hits.append(("field", hit(l.field.rect))) }
                        if l.listen.isShown { hits.append(("listen", hit(l.listen.rect))) }
                        if l.cancel.isShown { hits.append(("cancel", hit(l.cancel.rect))) }
                        if l.pill.isShown {
                            let n = CGFloat(ChromeDestination.allCases.count), slot = l.pill.rect.width / n
                            for i in 0..<Int(n) {
                                hits.append(("segment \(i)", hit(CGRect(x: l.pill.rect.minX + CGFloat(i) * slot, y: l.pill.rect.minY,
                                                                       width: slot, height: l.pill.rect.height), .segment)))
                            }
                        }
                        // The lit reader icon: a circle as tall as the field at its leading end.
                        let reader = hit(CGRect(x: l.field.rect.minX, y: l.field.rect.minY, width: Control.chrome, height: Control.chrome))
                        XCTAssertGreaterThanOrEqual(reader.width, Control.tap - 0.01, "the reader icon: \(tag)")
                        XCTAssertGreaterThanOrEqual(reader.height, Control.tap - 0.01, "the reader icon: \(tag)")
                        for (name, rect) in hits {
                            XCTAssertGreaterThanOrEqual(rect.width, Control.tap - 0.01, "\(name) wide enough: \(tag)")
                            XCTAssertGreaterThanOrEqual(rect.height, Control.tap - 0.01, "\(name) tall enough: \(tag)")
                            if name != "field" {
                                XCTAssertLessThan(area(rect.intersection(reader)), 0.01, "\(name) overlaps the reader icon: \(tag)")
                            }
                        }
                        for (i, a) in hits.enumerated() {
                            for b in hits[(i + 1)...] {
                                XCTAssertLessThan(area(a.1.intersection(b.1)), 0.01, "\(a.0) and \(b.0) overlap: \(tag)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    func testTheRowsEndOnTheHomeIndicatorStrip() {
        let browse = layout(.browse, back: true, forward: true)
        XCTAssertEqual(browse.field.rect.minY + Control.chrome + Spacing.xs, browse.pill.rect.minY, "row 1 over row 2")
        XCTAssertEqual(browse.nav.rect.width, M.navPairWidth)
        XCTAssertEqual(browse.top, browse.field.rect.minY)
        XCTAssertEqual(browse.field.rect.minY, Spacing.xxs, "row 1 at the top of the box")
        func library(home: CGFloat) -> ChromeLayout {
            ChromeLayout(width: 375, state: { var s = ChromeState(destination: .library); s.homeInset = home; return s }())
        }
        for home in [34.0, 21, 18].map({ CGFloat($0) }) {
            let l = library(home: home)
            XCTAssertEqual(l.pill.rect.maxY, M.rowsHeight, "row 2 ends on the \(home) pt strip's top, the box's foot")
            XCTAssertEqual(M.rowsHeight - l.top! + Spacing.xxs, M.clearance(step: 0, home: home),
                           "what it covers, with the room above row 1, is what screens reserve: \(home)")
        }
        let se = library(home: 0)
        XCTAssertEqual(M.rowsHeight + 0 - se.pill.rect.maxY, M.bubbleClearance, "with a Home button: as far above the edge as the bubble")
        XCTAssertEqual(M.rowsHeight - se.top! + Spacing.xxs, M.clearance(step: 0, home: 0))
    }

    /// The fold's steps: two rows, then one (row 2 gone, row 1 in its place), then the bubble.
    func testFoldingGoesTwoRowsThenOneThenTheBubble() {
        let expanded = layout(.browse, progress: 0, back: true)
        let one = layout(.browse, progress: 0.5, back: true)
        let folded = layout(.browse, progress: 1, back: true)
        XCTAssertFalse(expanded.bubble.isShown)
        XCTAssertFalse(one.pill.isShown, "one row: row 2 gone")
        XCTAssertTrue(one.field.isShown && one.nav.isShown && one.listen.isShown)
        XCTAssertFalse(one.bubble.isShown)
        XCTAssertEqual(one.field.rect, expanded.field.rect.offsetBy(dx: 0, dy: Control.tabBar + Spacing.xs), "row 1 drops into row 2's place")
        XCTAssertEqual(one.listen.rect, expanded.listen.rect.offsetBy(dx: 0, dy: Control.tabBar + Spacing.xs), "Listen with it")
        XCTAssertEqual(one.field.rect.maxY, expanded.pill.rect.maxY, "ending where row 2 ended")
        XCTAssertEqual(one.top, one.field.rect.minY)
        XCTAssertEqual([folded.pill, folded.field, folded.nav, folded.cancel, folded.listen].map(\.isShown),
                       Array(repeating: false, count: 5), "folded: nothing but the bubble")
        XCTAssertTrue(folded.bubble.isShown)
        XCTAssertEqual(folded.bubble.opacity, 1)
        let first = layout(.browse, progress: 0.2, back: true)
        XCTAssertGreaterThan(first.pill.rect.minY, expanded.pill.rect.minY, "row 2 slides down")
        XCTAssertGreaterThan(first.field.rect.minY, expanded.field.rect.minY, "while row 1 drops")
        XCTAssertEqual(first.field.rect.width, expanded.field.rect.width, "row 1 keeps its size in the first step")
        var last: CGFloat = -1
        for step in 0...20 {
            let o = layout(.browse, progress: CGFloat(step) / 20).bubble.opacity
            if layout(.browse, progress: CGFloat(step) / 20).bubble.isShown {
                XCTAssertGreaterThanOrEqual(o, last, "the bubble's name only comes up as the rows fold")
                last = o
            }
        }
    }

    /// Every piece folds straight down, never sideways, and the field shrinks into the bubble: the bubble's
    /// glass takes over at the field's rect (one shape, no jump) and shrinks to its own, its name starting
    /// where the field's text is, at its size, and ending centred at the bubble's.
    func testTheRowsGoDownAndTheFieldShrinksIntoTheBubble() {
        let expanded = layout(.browse, progress: 0, back: true, forward: true)
        let one = layout(.browse, progress: 0.5, back: true, forward: true)
        var lastWidth = CGFloat.infinity
        for step in 1...20 {
            let l = layout(.browse, progress: CGFloat(step) / 20, back: true, forward: true)
            for (piece, start) in [(l.pill, expanded.pill), (l.nav, expanded.nav), (l.listen, expanded.listen)] where piece.isShown {
                XCTAssertEqual(piece.rect.minX, start.rect.minX, "no sideways travel at step \(step)")
                XCTAssertEqual(piece.rect.size, start.rect.size, "no shrinking at step \(step)")
                XCTAssertGreaterThanOrEqual(piece.rect.minY, start.rect.minY, "down at step \(step)")
            }
            guard l.bubble.isShown else { continue }
            XCTAssertLessThanOrEqual(l.bubble.rect.width, lastWidth, "step \(step)")
            lastWidth = l.bubble.rect.width
            if l.field.isShown {
                XCTAssertEqual(l.bubble.rect, one.field.rect, "while the field is there the bubble is under it, its shape")
                XCTAssertEqual(l.bubbleTextX, M.fieldTextInset, "the name is where the field's text is")
                XCTAssertEqual(l.bubbleTextScale * TypeStyle.caption.size, TypeStyle.row.size, accuracy: 0.001, "at its size")
            }
        }
        let folded = layout(.browse, progress: 1, back: true, forward: true)
        XCTAssertEqual(folded.bubbleTextX, Spacing.m, "centred in the bubble")
        XCTAssertEqual(folded.bubbleTextScale, 1)
        XCTAssertFalse(layout(.browse, progress: 0.7).field.isShown, "the field has handed its glass over")
    }

    /// The bubble at the two phones that matter (the 17 Pro's 402, the SE's 375): 36 pt of glass as wide as its
    /// name and padding (to the margins), centred, ending 18 above the screen's edge, a 44 pt hit area, nothing else on screen.
    func testTheBubbleIsASmallCapsuleAboveTheHomeIndicatorWithA44HitArea() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for (text, expected) in [(0.0, 36.0), (60.0, 92), (110, 142), (500, Double(width) - 2 * Double(Spacing.bandMargin))] {
                    let bubbleWidth = M.bubbleWidth(forTextWidth: CGFloat(text))
                    let l = ChromeLayout(width: width, state: ChromeState(destination: destination, progress: 1,
                                                                          canGoBack: true, canGoForward: true, bubbleWidth: bubbleWidth))
                    let tag = "\(width) \(destination) \(text)"
                    XCTAssertTrue(l.bubble.isShown, tag)
                    XCTAssertEqual(l.bubble.rect.height, 36, tag)
                    XCTAssertEqual(l.bubble.rect.width, CGFloat(expected), tag)
                    XCTAssertEqual(l.bubble.rect.midX, width / 2, tag)
                    XCTAssertEqual(l.bubble.rect.maxY, M.rowsHeight + 34 - M.bubbleClearance, "bubbleClearance above the screen's edge: \(tag)")
                    XCTAssertEqual(M.rowsHeight - l.bubble.rect.minY, M.clearance(step: 2, home: 34) - Spacing.xxs, "inside what it covers: \(tag)")
                    let hit = l.bubble.rect.insetBy(dx: 0, dy: -M.bubbleHitOutset)
                    XCTAssertEqual(hit.height, 44, tag)
                    XCTAssertEqual(l.top, l.bubble.rect.minY, "nothing else is on screen: \(tag)")
                }
            }
        }
    }

    func testTheBubbleIsOnlyThereFoldedAndNeverTypingOrEditing() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            XCTAssertFalse(layout(.browse, width: width, progress: 0).bubble.isShown, "expanded")
            XCTAssertFalse(layout(.browse, width: width, progress: 0.5).bubble.isShown, "one row")
            XCTAssertFalse(layout(.library, width: width, progress: 1, keyboard: true).bubble.isShown, "typing")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .library, progress: 1, editing: true)).bubble.isShown, "Edit")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 1, fullScreen: true)).bubble.isShown, "full screen")
        }
    }

    func testBrowseAlwaysHasBackAndNothingElseDoes() {
        XCTAssertTrue(layout(.browse).nav.isShown, "a new page keeps ‹")
        XCTAssertFalse(layout(.library, back: true).nav.isShown, "only the Browser has arrows")
        XCTAssertFalse(layout(.settings, back: true).nav.isShown, "only the Browser has arrows")
    }

    func testEditBarReplacesRowTwoAndFullScreenShowsNothing() {
        let edit = ChromeLayout(width: 393, state: ChromeState(destination: .library, editing: true))
        XCTAssertTrue(edit.editBar.isShown)
        XCTAssertEqual([edit.pill, edit.cancel, edit.listen].map(\.isShown), [false, false, false])
        let full = ChromeLayout(width: 393, state: ChromeState(destination: .browse, fullScreen: true, readerMode: true))
        XCTAssertEqual([full.pill, full.field, full.nav, full.listen, full.cancel, full.editBar].map(\.isShown),
                       Array(repeating: false, count: 6))
        XCTAssertNil(full.top)
    }

    // MARK: Scroll

    /// A controller handed to the Library's home, as on its screens.
    @MainActor
    private func libraryChrome() -> ChromeScroll {
        let chrome = ChromeScroll()
        chrome.hand(to: ChromeOwner(source: .library))
        return chrome
    }

    /// A controller handed to Library Read in Scroll mode.
    @MainActor
    private func readerChrome() -> ChromeScroll {
        let chrome = ChromeScroll()
        chrome.hand(to: ChromeOwner(source: .libraryReader))
        XCTAssertEqual(chrome.policy, .reads(scrollHides: true))
        return chrome
    }

    @MainActor
    private func scroll(_ chrome: ChromeScroll, to offsets: [CGFloat], from source: ChromeSource = .library) {
        offsets.forEach { chrome.scrolled(to: $0, from: source) }
    }

    @MainActor
    func testProgressFollowsTheFingerDownSixtyPointsAStepAndAScrollUpRevealsBothRows() {
        let chrome = libraryChrome()
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [70])
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "60 pt: one row")
        scroll(chrome, to: [200])
        XCTAssertEqual(chrome.progress, 1, "clamped: the bubble")
        scroll(chrome, to: [180])
        XCTAssertEqual(chrome.progress, 1, "a short scroll up gives nothing back")
        scroll(chrome, to: [175])
        XCTAssertEqual(chrome.progress, 0, "24 pt up brings both rows back")
        scroll(chrome, to: [195, 190, 200])
        XCTAssertEqual(chrome.progress, 30 / ChromeScroll.travel, accuracy: 0.001, "5 pt up between two scrolls down reveals nothing")
    }

    @MainActor
    func testAFoldStoppedBetweenStepsFinishesItsStep() {
        let down = libraryChrome()
        down.anchor(at: 10, from: .library)
        scroll(down, to: [40])
        down.settle()
        XCTAssertEqual(down.progress, 0.5, "a first step stopped partway ends at one row")
        scroll(down, to: [60])
        down.settle()
        XCTAssertEqual(down.progress, 1, "a second step stopped partway ends at the bubble")
        let reverse = libraryChrome()
        reverse.anchor(at: 10, from: .library)
        scroll(reverse, to: [40, 30, 20, 12, 10])
        reverse.settle()
        XCTAssertEqual(reverse.progress, 0, "turning back 30 pt brings both rows back")
        XCTAssertEqual([0, 0.1, 0.5, 0.6, 1].map { ChromeScroll.stepEnd(CGFloat($0)) }, [0, 0.5, 0.5, 1, 1])
        XCTAssertEqual([0, 0.2, 0.5, 0.74, 0.8, 1].map { ChromeScroll.step(CGFloat($0)) }, [0, 0, 1, 1, 2, 2])
    }

    /// The bubble's tap brings both rows back for a short scroll down only: past `refoldGrace` they fold
    /// again (no lasting pin); a fling under way at the tap moves nothing for `tapQuiet`.
    @MainActor
    func testATapExpandFoldsAgainAfterAShortScrollDown() async throws {
        let chrome = libraryChrome()
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [70, 130, 190])
        XCTAssertEqual(chrome.progress, 1)
        chrome.expandByHand()
        XCTAssertEqual(chrome.progress, 0)
        XCTAssertEqual(chrome.grace, ChromeScroll.refoldGrace)
        scroll(chrome, to: [260, 400])
        XCTAssertEqual(chrome.progress, 0, "a fling already under way does not fold it")
        try await Task.sleep(for: .milliseconds(Int(ChromeScroll.tapQuiet * 1000) + 50))
        scroll(chrome, to: [410, 420])
        XCTAssertEqual(chrome.progress, 0, "inside the grace: the rows stay")
        scroll(chrome, to: [430])
        XCTAssertEqual(chrome.progress, 6 / ChromeScroll.travel, accuracy: 0.001, "past 24 pt it folds again")
        scroll(chrome, to: [420, 300])
        XCTAssertEqual(chrome.progress, 0, "and a scroll up brings it back")
        scroll(chrome, to: [3])
        XCTAssertEqual(chrome.grace, 0)
    }

    @MainActor
    func testANewScreenOrPageClearsTheGrace() {
        for clear in [{ (c: ChromeScroll) in c.hand(to: ChromeOwner(source: .library, screen: "folder")) }, { $0.expand() }] {
            let chrome = libraryChrome()
            chrome.anchor(at: 10, from: .library)
            chrome.expandByHand()
            clear(chrome)
            XCTAssertEqual(chrome.grace, 0)
            scroll(chrome, to: [70, 130, 190])
            XCTAssertEqual(chrome.progress, 1)
        }
    }

    @MainActor
    func testAHeldDestinationNeverFoldsAndLeavingItStartsExpanded() {
        let chrome = libraryChrome()
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [130])
        XCTAssertEqual(chrome.progress, 1, "a Library scrolled down")
        chrome.conditions.editing = [.library]
        XCTAssertEqual(chrome.policy, .holds)
        XCTAssertEqual(chrome.progress, 0, "Edit on a folded Library: expanded")
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [60, 120, 200, 300])
        XCTAssertEqual(chrome.progress, 0)
        chrome.hand(to: ChromeOwner(source: .settings))
        XCTAssertEqual(chrome.policy, .folds, "the Library's Edit is the Library's alone")
        chrome.anchor(at: 10, from: .settings)
        scroll(chrome, to: [130], from: .settings)
        XCTAssertEqual(chrome.progress, 1, "other destinations fold again")
        chrome.conditions.browserHasPage = false
        chrome.hand(to: ChromeOwner(source: .browser))
        XCTAssertEqual(chrome.policy, .holds, "the start page holds, in the same step as the handover")
        XCTAssertEqual(chrome.progress, 0)
    }

    @MainActor
    func testTheKeyboardIgnoresScrollingAndANewScreenLeavesFullScreen() {
        let chrome = libraryChrome()
        chrome.isLocked = true
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [80])
        XCTAssertEqual(chrome.progress, 0, "keyboard up")
        chrome.isLocked = false
        let first = ChromeOwner(source: .libraryReader, screen: 1)
        chrome.hand(to: first)
        chrome.setFullScreen(true, from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen)
        chrome.hand(to: ChromeOwner(source: .libraryReader, screen: 2))
        XCTAssertFalse(chrome.fullScreen, "another page read in place starts expanded, out of full screen")
        chrome.setFullScreen(true, from: .libraryReader)
        chrome.hand(to: ChromeOwner(source: .library))
        XCTAssertFalse(chrome.fullScreen, "full screen exists only on a reader")
        chrome.setFullScreen(true, from: .library)
        XCTAssertFalse(chrome.fullScreen, "nor can a screen that folds ask for it")
    }

    @MainActor
    func testAProgrammaticMoveMovesNothingAndTheTopStillExpands() {
        let chrome = libraryChrome()
        chrome.anchor(at: 295, from: .library)
        scroll(chrome, to: [296, 1000])
        XCTAssertEqual(chrome.progress, 1 / ChromeScroll.travel, accuracy: 0.001, "a 700 pt jump is not a finger")
        scroll(chrome, to: [200, 100])
        chrome.anchor(at: 0, from: .library)
        XCTAssertEqual(chrome.progress, 0)
    }

    /// Only the screen showing moves the chrome: the Browser's page under the Library and the Library under
    /// Library Read are refused without touching the owner's baseline; while Listen is up (no owner) nothing
    /// counts, and after it the first report only sets a fresh baseline, so a fling's travel from before never
    /// lands at once. The reader's centre tap is gated the same way.
    @MainActor
    func testOnlyTheDrivingSurfaceMovesTheChrome() {
        let chrome = ChromeScroll()
        let library = ChromeOwner(source: .library)
        chrome.hand(to: library)
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [310], from: .browser)
        scroll(chrome, to: [310], from: .libraryReader)
        XCTAssertEqual(chrome.progress, 0, "a surface under the Library moves nothing")
        scroll(chrome, to: [70], from: .library)
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "the Library measures from its own baseline")

        chrome.hand(to: nil)
        scroll(chrome, to: [100, 400], from: .library)
        scroll(chrome, to: [400], from: .browser)
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "Listen up: nothing under it drives")
        chrome.hand(to: library)
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "a cover gone: the same screen, as it was left")
        scroll(chrome, to: [420], from: .library)
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "back: the first report is a fresh baseline")
        scroll(chrome, to: [450], from: .library)
        XCTAssertEqual(chrome.progress, 0.75, accuracy: 0.001)

        chrome.anchor(at: 450, from: .library)
        scroll(chrome, to: [470], from: .library)
        chrome.hand(to: nil)
        chrome.hand(to: library)
        scroll(chrome, to: [480], from: .library)
        XCTAssertEqual(chrome.progress, 0.75 + 20 / ChromeScroll.travel, accuracy: 0.001,
                       "suspended and resumed without a report between: the travel before it is dropped all the same")

        let reader = ChromeOwner(source: .browserReader, screen: 1)
        chrome.hand(to: reader)
        XCTAssertEqual(chrome.progress, 0, "a page read in place is a new screen: expanded")
        chrome.anchor(at: 100, from: .browserReader)
        scroll(chrome, to: [400], from: .browser)
        scroll(chrome, to: [400], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "a reader: the surfaces under it hide nothing")
        scroll(chrome, to: [159], from: .browserReader)
        XCTAssertFalse(chrome.fullScreen, "59 pt from the reader's own baseline")
        scroll(chrome, to: [140, 159], from: .browserReader)
        XCTAssertFalse(chrome.fullScreen, "the 19 pt back up is taken off the travel")
        scroll(chrome, to: [160], from: .browserReader)
        XCTAssertTrue(chrome.fullScreen)
        chrome.hand(to: nil)
        for source in [ChromeSource.browserReader, .browser, .library] { scroll(chrome, to: [0], from: source) }
        chrome.setFullScreen(false, from: .browserReader)
        XCTAssertTrue(chrome.fullScreen, "under Listen nothing reveals the reader, its tap included")
        chrome.hand(to: reader)
        XCTAssertTrue(chrome.fullScreen, "closing Listen leaves the reader as it was")
        scroll(chrome, to: [700], from: .browserReader)
        scroll(chrome, to: [680], from: .browserReader)
        XCTAssertTrue(chrome.fullScreen, "after Listen a fling's first report is a baseline, then 20 up stays")
        chrome.hand(to: library)
        XCTAssertFalse(chrome.fullScreen, "on the Library full screen is off")
        chrome.setFullScreen(true, from: .browserReader)
        XCTAssertFalse(chrome.fullScreen, "the Browser's reader, still mounted under the Library, writes nothing")

        // Two suspensions in a row, a baseline set between them: neither leaks travel.
        chrome.hand(to: reader)
        chrome.anchor(at: 100, from: .browserReader)
        chrome.hand(to: nil)
        chrome.hand(to: reader)
        scroll(chrome, to: [200], from: .browserReader)
        chrome.hand(to: nil)
        scroll(chrome, to: [250], from: .browserReader)
        chrome.hand(to: reader)
        scroll(chrome, to: [260], from: .browserReader)
        XCTAssertFalse(chrome.fullScreen, "the first report after each resume is only a baseline")
        scroll(chrome, to: [319], from: .browserReader)
        XCTAssertFalse(chrome.fullScreen)
        scroll(chrome, to: [320], from: .browserReader)
        XCTAssertTrue(chrome.fullScreen, "60 pt from the fresh baseline")
    }

    /// The shell suspends the chrome under anything that covers the screen showing, a sheet included.
    @MainActor
    func testListenTheReaderAndAnySheetSuspendTheChrome() {
        let shell = ShellState()
        XCTAssertEqual(shell.chromeScroll.driver, .browser)
        shell.present(.history)
        XCTAssertNil(shell.chromeScroll.driver, "a sheet over the Browser")
        shell.sheet = nil
        XCTAssertEqual(shell.chromeScroll.driver, .browser)
        shell.isPickingBook = true
        XCTAssertNil(shell.chromeScroll.driver, "the Files picker")
        shell.isPickingBook = false
        shell.showNowPlaying()
        XCTAssertNil(shell.chromeScroll.driver, "Listen")
        shell.hideNowPlaying()
        shell.openLibrary()
        XCTAssertEqual(shell.chromeScroll.driver, .library)
        let chrome = shell.chromeScroll
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [130])
        shell.present(.history)
        shell.sheet = nil
        XCTAssertEqual(chrome.progress, 1, "a sheet covers the Library; gone, the Library is as it was left")
        shell.libraryPath = [.folder(UUID())]
        XCTAssertEqual(chrome.progress, 0, "a pushed folder is a new screen, handed over in the same step")
    }

    /// A browser page that changes while another screen owns the chrome, or under a cover, leaves that
    /// screen's fold alone (and no settle runs under a cover); the Browser comes back expanded on its new page.
    @MainActor
    func testABrowserPageChangeOrAPendingSettleNeverMovesAnotherScreensChrome() async throws {
        let shell = ShellState()
        let chrome = shell.chromeScroll
        shell.openLibrary()
        chrome.anchor(at: 10, from: .library)
        scroll(chrome, to: [130])
        shell.web.currentURL = URL(string: "https://example.com/one")
        shell.browserPageChanged()
        XCTAssertEqual(chrome.progress, 1, "a page loading under the Library")
        shell.showNowPlaying()
        shell.web.currentURL = URL(string: "https://example.com/two")
        shell.browserPageChanged()
        shell.hideNowPlaying()
        XCTAssertEqual(chrome.progress, 1, "a page loading under Listen over the Library")
        chrome.anchor(at: 0, from: .library)
        scroll(chrome, to: [30])
        let partway = chrome.progress
        XCTAssertNotEqual(partway, ChromeScroll.stepEnd(partway))
        shell.showNowPlaying()
        try await Task.sleep(for: ChromeScroll.settleDelay * 2)
        XCTAssertEqual(chrome.progress, partway, "no settle under Listen")
        shell.hideNowPlaying()
        try await Task.sleep(for: ChromeScroll.settleDelay * 2)
        XCTAssertEqual(chrome.progress, ChromeScroll.stepEnd(partway), "back, the fold finishes its step")
        shell.showBrowser()
        XCTAssertEqual(chrome.progress, 0, "the Browser on its new page starts expanded")
    }

    /// A reader is expanded or full screen: 60 pt of one gesture down enters, 24 pt up leaves, and it never folds.
    @MainActor
    func testAReaderGoesFullScreenAfterADeliberateScrollDownAndBackAfter24Up() {
        let chrome = readerChrome()
        chrome.anchor(at: 10, from: .libraryReader)
        scroll(chrome, to: [40, 69], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "59 pt: still expanded")
        scroll(chrome, to: [70], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "60 pt: full screen")
        XCTAssertEqual(chrome.progress, 0, "a reader never folds")
        scroll(chrome, to: [60, 47], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "23 pt up: still full screen")
        scroll(chrome, to: [46], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "24 pt up: back")
        scroll(chrome, to: [100], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "after a reveal re-hiding takes a fresh 60 pt")
        scroll(chrome, to: [106], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen)
        XCTAssertEqual(chrome.progress, 0)
    }

    /// The rebound from a pull past the top never hides; the pull itself reveals.
    @MainActor
    func testTheTopReboundNeverHidesAndThePullReveals() {
        let chrome = readerChrome()
        chrome.anchor(at: 0, from: .libraryReader)
        chrome.setFullScreen(true, from: .libraryReader)
        scroll(chrome, to: [-20], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen)
        scroll(chrome, to: [-40, -60, -80], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "the pull is a scroll up: back from -24")
        scroll(chrome, to: [-60, -40, -20, 0], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "the rebound is clamped at the top: no travel")
        scroll(chrome, to: [60], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "a real 60 pt down")
    }

    /// A move (a restore, a reflow, a jump, a gesture's start) never toggles a reader, and re-anchors the travel.
    @MainActor
    func testAMoveNeverTogglesAReader() {
        let chrome = readerChrome()
        chrome.anchor(at: 300, from: .libraryReader)
        chrome.setFullScreen(true, from: .libraryReader)
        chrome.anchor(at: 0, from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "the top reached by a move keeps full screen")
        scroll(chrome, to: [700], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "a 700 pt jump is not a finger")
        chrome.setFullScreen(false, from: .libraryReader)
        chrome.anchor(at: 100, from: .libraryReader)
        scroll(chrome, to: [140], from: .libraryReader)
        chrome.anchor(at: 140, from: .libraryReader)
        scroll(chrome, to: [180], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "two 40 pt gestures never add up")
    }

    /// Pages mode and VoiceOver: full screen by the tap alone, kept across the switch between the two rules.
    @MainActor
    func testPagesAndVoiceOverReadersToggleOnlyByTheTap() {
        let chrome = readerChrome()
        chrome.conditions.readsByScroll = false
        XCTAssertEqual(chrome.policy, .reads(scrollHides: false))
        chrome.anchor(at: 10, from: .libraryReader)
        scroll(chrome, to: [310], from: .libraryReader)
        XCTAssertFalse(chrome.fullScreen, "Pages: a scroll hides nothing")
        chrome.setFullScreen(true, from: .libraryReader)
        scroll(chrome, to: [200, 100, 50], from: .libraryReader)
        XCTAssertTrue(chrome.fullScreen, "nor reveals")
        chrome.conditions.readsByScroll = true
        XCTAssertTrue(chrome.fullScreen, "Pages to Scroll keeps full screen")
        chrome.conditions.voiceOver = true
        XCTAssertTrue(chrome.fullScreen)
        XCTAssertEqual(chrome.progress, 0)
    }

    func testSwipeUpIsPastTheDistanceAndMoreUpThanAcross() {
        XCTAssertTrue(ChromeScroll.isSwipeUp(CGSize(width: 5, height: -40)))
        XCTAssertFalse(ChromeScroll.isSwipeUp(CGSize(width: 5, height: -20)))
        XCTAssertFalse(ChromeScroll.isSwipeUp(CGSize(width: 60, height: -40)))
    }
}
