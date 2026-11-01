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
        state.readerMode = true
        XCTAssertEqual(state.collapse, 1, "reader mode in Scroll mode folds like a page (the host holds Pages mode expanded)")
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

    /// Listen is a bar-sized disc ending row 1 on every destination, reader modes too, and the field
    /// gives it its room; typing and Edit have none, and the field runs to the margin.
    func testListenEndsRowOneOnEveryDestinationAndTheFieldYieldsToIt() {
        let width: CGFloat = 393
        for destination in ChromeDestination.allCases {
            for readerMode in [false, true] {
                let l = ChromeLayout(width: width, state: ChromeState(destination: destination, canGoBack: readerMode,
                                                                      readerMode: readerMode))
                let tag = "\(destination) reader mode \(readerMode)"
                XCTAssertTrue(l.listen.isShown, tag)
                XCTAssertEqual(l.listen.rect.width, Control.bar, tag)
                XCTAssertEqual(l.listen.rect.height, Control.bar, tag)
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

    // MARK: Tokens

    func testOneBarHeightDerivesEveryFootprintAndWidth() {
        XCTAssertEqual(Control.bar, 48, "Safari's")
        XCTAssertEqual(M.rowsHeight, 108, "4 + 48 + 8 + 48, its foot on the safe area")
        let steps = [0, 1, 2]
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 34) }, [108, 52, 24], "above a 34 pt strip")
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 34) + 34 }, [142, 86, 58], "Safari's, from the screen's edge")
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 21) }, [108, 52, 37], "a 21 pt strip: the rows still end on it")
        XCTAssertEqual(steps.map { M.clearance(step: $0, home: 0) }, [126, 70, 58],
                       "a Home button phone: the rows end 18 above the edge, as the bubble does")
        XCTAssertEqual(M.keyboardClearance, 52, "the keyboard's row: 4 + 48 over the keyboard")
        XCTAssertEqual(M.navSingleWidth, 48)
        XCTAssertEqual(M.navPairWidth, 96)
        XCTAssertEqual([Control.small, M.bubbleClearance, TypeStyle.caption.size, Spacing.m], [36, 18, 13, 16])
        XCTAssertEqual(M.bubbleHitOutset, 4, "36 + 2 * 4 = the 44 pt hit area")
        XCTAssertEqual(M.hitOutset, 0, "48 is already past the 44 pt hit area")
        XCTAssertGreaterThanOrEqual(Spacing.xs, 2 * M.hitOutset, "the rows' hit areas never overlap")
        XCTAssertEqual([M.endGlyphSlot, M.endInset], [24, 12], "concentric: a 24 slot 12 in from a 48 pill's end")
        XCTAssertEqual(Control.bar / 2 - M.endInset, M.endGlyphSlot / 2, "inner radius = outer - inset")
        XCTAssertEqual(Control.bar - 2 * Spacing.xxs, 40, "the lit segment")
        XCTAssertGreaterThanOrEqual(Control.tap, 44)
    }

    // MARK: Layout

    func testExpandedWidthsAtEveryPhone() {
        // Row 1 less the margins and Listen's disc and gap: 351 - 46 on the SE, less ‹ › and a gap with arrows.
        for (width, both, none) in [(375.0, 191.0, 295.0), (393, 209, 313), (430, 246, 350)] {
            let w = CGFloat(width)
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
                XCTAssertEqual(l.cancel.rect.height, Control.bar, tag)
                XCTAssertEqual(l.cancel.rect.minX - l.field.rect.maxX, Spacing.xs, tag)
                XCTAssertEqual(l.field.rect.width, width - 2 * Spacing.bandMargin - Spacing.xs - M.cancelWidth, tag)
                // On the keyboard, not dipped into the home indicator's strip: the row ends at the box's bottom.
                XCTAssertEqual(l.field.rect.maxY, M.rowsHeight, "the row sits on the keyboard: \(tag)")
                XCTAssertEqual(l.cancel.rect.minY, l.field.rect.minY, tag)
                XCTAssertFalse(rest.cancel.isShown, "Cancel only while typing: \(tag)")
                XCTAssertLessThanOrEqual(l.field.rect.minY, rest.pill.rect.minY, "never below the resting row 2: \(tag)")
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

    func testEveryPieceIsAsTallAsTheBarWideEnoughToTapAndInsideTheMargins() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for (progress, keyboard) in [(0.0, false), (1.0, false), (0.0, true)] {
                    let l = layout(destination, width: width, progress: CGFloat(progress), back: true, forward: true, keyboard: keyboard)
                    let tag = "\(width) \(destination) progress \(progress) keyboard \(keyboard)"
                    let shown = [l.pill, l.field, l.nav, l.listen, l.cancel].filter(\.isShown)
                    for piece in shown {
                        XCTAssertEqual(piece.rect.height, Control.bar, tag)
                        XCTAssertGreaterThanOrEqual(piece.rect.width + 2 * M.hitOutset, Control.tap, "a 44 pt hit area with the outset: \(tag)")
                        XCTAssertGreaterThanOrEqual(piece.rect.minX, Spacing.bandMargin - 0.01, tag)
                        XCTAssertLessThanOrEqual(piece.rect.maxX, width - Spacing.bandMargin + 0.01, tag)
                        XCTAssertEqual(piece.radius, Control.bar / 2, "capsule \(tag)")
                    }
                    for (i, a) in shown.enumerated() {
                        for b in shown[(i + 1)...] where abs(a.rect.minY - b.rect.minY) < Control.bar / 2 {
                            let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
                            XCTAssertGreaterThanOrEqual(gap, Spacing.xs - 0.01, tag)
                        }
                    }
                    // Every hit area (the glass and `hitOutset` round it) is 44 tall and overlaps no other.
                    let hits = shown.map { $0.rect.insetBy(dx: -M.hitOutset, dy: -M.hitOutset) }
                    for (i, a) in hits.enumerated() {
                        XCTAssertEqual(a.height, max(Control.tap, Control.bar), tag)
                        for b in hits[(i + 1)...] {
                            XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).width * a.intersection(b).height < 0.01, "hit areas overlap: \(tag)")
                        }
                    }
                }
            }
        }
    }

    func testTheRowsEndOnTheHomeIndicatorStrip() {
        let browse = layout(.browse, back: true, forward: true)
        XCTAssertEqual(browse.field.rect.minY + Control.bar + Spacing.xs, browse.pill.rect.minY, "row 1 over row 2")
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
        XCTAssertEqual(M.rowsHeight + 0 - se.pill.rect.maxY, M.bubbleClearance, "with a Home button: 18 above the edge, as the bubble")
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
        XCTAssertEqual(one.field.rect, expanded.field.rect.offsetBy(dx: 0, dy: Control.bar + Spacing.xs), "row 1 drops into row 2's place")
        XCTAssertEqual(one.listen.rect, expanded.listen.rect.offsetBy(dx: 0, dy: Control.bar + Spacing.xs), "Listen with it")
        XCTAssertEqual(one.field.rect.minY, expanded.pill.rect.minY)
        XCTAssertEqual(one.top, expanded.pill.rect.minY)
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
                    XCTAssertEqual(l.bubble.radius, 18, "a capsule: \(tag)")
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

    @MainActor
    private func scroll(_ chrome: ChromeScroll, to offsets: [CGFloat]) { offsets.forEach { chrome.scrolled(to: $0) } }

    @MainActor
    func testProgressFollowsTheFingerDownSixtyPointsAStepAndAScrollUpRevealsBothRows() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
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
        let down = ChromeScroll()
        down.anchor(at: 10)
        scroll(down, to: [40])
        down.settle()
        XCTAssertEqual(down.progress, 0.5, "a first step stopped partway ends at one row")
        scroll(down, to: [60])
        down.settle()
        XCTAssertEqual(down.progress, 1, "a second step stopped partway ends at the bubble")
        let reverse = ChromeScroll()
        reverse.anchor(at: 10)
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
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
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
        for clear in [{ (c: ChromeScroll) in c.reset() }, { $0.expand() }] {
            let chrome = ChromeScroll()
            chrome.anchor(at: 10)
            chrome.expandByHand()
            clear(chrome)
            XCTAssertEqual(chrome.grace, 0)
            scroll(chrome, to: [70, 130, 190])
            XCTAssertEqual(chrome.progress, 1)
        }
    }

    @MainActor
    func testAHeldDestinationNeverFoldsAndLeavingItStartsExpanded() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [130])
        XCTAssertEqual(chrome.progress, 1, "a Library scrolled down")
        chrome.holdsExpanded = true
        XCTAssertEqual(chrome.progress, 0, "coming to a held screen (Pages mode, Edit) from a folded Library: expanded")
        chrome.anchor(at: 10)
        scroll(chrome, to: [60, 120, 200, 300])
        XCTAssertEqual(chrome.progress, 0)
        chrome.holdsExpanded = false
        chrome.reset()
        scroll(chrome, to: [130])
        XCTAssertEqual(chrome.progress, 1, "other destinations fold again")
    }

    @MainActor
    func testTheKeyboardAndFullScreenIgnoreScrolling() {
        let chrome = ChromeScroll()
        chrome.isLocked = true
        chrome.anchor(at: 10)
        scroll(chrome, to: [80])
        XCTAssertEqual(chrome.progress, 0, "keyboard or ⋯ panel up")
        chrome.isLocked = false
        chrome.setFullScreen(true)
        scroll(chrome, to: [100, 200])
        XCTAssertEqual(chrome.progress, 0, "full screen is the middle tap's alone")
        XCTAssertTrue(chrome.fullScreen, "scrolling never leaves it")
        chrome.reset()
        XCTAssertFalse(chrome.fullScreen, "a new screen starts expanded, out of full screen")
    }

    @MainActor
    func testAProgrammaticMoveMovesNothingAndTheTopStillExpands() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 295)
        scroll(chrome, to: [296, 1000])
        XCTAssertEqual(chrome.progress, 1 / ChromeScroll.travel, accuracy: 0.001, "a 700 pt jump is not a finger")
        scroll(chrome, to: [200, 100])
        chrome.anchor(at: 0)
        XCTAssertEqual(chrome.progress, 0)
    }

    func testSwipeUpIsPastTheDistanceAndMoreUpThanAcross() {
        XCTAssertTrue(ChromeScroll.isSwipeUp(CGSize(width: 5, height: -40)))
        XCTAssertFalse(ChromeScroll.isSwipeUp(CGSize(width: 5, height: -20)))
        XCTAssertFalse(ChromeScroll.isSwipeUp(CGSize(width: 60, height: -40)))
    }
}
