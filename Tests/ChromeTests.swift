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

    func testEditHoldsTheChromeExpandedAndTheKeyboardHidesTheStrip() {
        var state = ChromeState(destination: .browse, progress: 1)
        XCTAssertEqual(state.collapse, 1)
        XCTAssertEqual(state.fold, 1)
        state.readerMode = true
        XCTAssertEqual(state.collapse, 1, "reader mode in Scroll mode folds like a page (the host holds Pages mode expanded)")
        state = ChromeState(destination: .library, progress: 1, editing: true)
        XCTAssertEqual(state.collapse, 0)
        let typing = ChromeState(destination: .library, progress: 1, keyboard: true)
        XCTAssertEqual(typing.fold, 0, "no strip while typing: the field's row is the only row")
    }

    func testEditKeepsBothRowsWhateverTheScroll() {
        let scrolled = ChromeLayout(width: 393, state: ChromeState(destination: .browse, progress: 1))
        let edit = ChromeLayout(width: 393, state: ChromeState(destination: .library, progress: 1, editing: true))
        XCTAssertTrue(scrolled.strip.isShown)
        XCTAssertFalse(scrolled.pill.isShown, "scrolled: the rows are the strip")
        XCTAssertFalse(edit.strip.isShown, "Edit: row 2 stays")
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
                XCTAssertEqual(l.listen.rect.width, M.barHeight, tag)
                XCTAssertEqual(l.listen.rect.height, M.barHeight, tag)
                XCTAssertEqual(l.listen.rect.maxX, width - M.margin, tag)
                XCTAssertEqual(l.listen.rect.minY, l.field.rect.minY, tag)
                XCTAssertEqual(l.field.rect.maxX + M.rowGap, l.listen.rect.minX, tag)
            }
        }
        let typing = layout(.browse, width: width, keyboard: true)
        XCTAssertFalse(typing.listen.isShown, "typing: the field and Cancel only")
        let edit = ChromeLayout(width: width, state: ChromeState(destination: .library, editing: true))
        XCTAssertFalse(edit.listen.isShown, "Edit: the search alone on row 1")
        XCTAssertEqual(edit.field.rect.maxX, width - M.margin, "the field runs to the margin without Listen")
    }

    // MARK: Tokens

    func testOneBarHeightDerivesEveryFootprintAndWidth() {
        XCTAssertEqual(M.barHeight, 48, "Safari's")
        XCTAssertEqual(M.edgeClearance, 34, "the bottom row ends where Safari's does")
        XCTAssertEqual(M.footprint, 142, "4 + 48 + 8 + 48 + 34, from the screen's edge")
        XCTAssertEqual(M.collapsedFootprint, 86, "one row: the keyboard's and the fold's first step")
        XCTAssertEqual(M.stripFootprint, 58, "the strip: 4 + 20 + 34")
        XCTAssertEqual([M.footprint(step: 0), M.footprint(step: 1), M.footprint(step: 2)], [142, 86, 58])
        XCTAssertEqual(M.aboveSafeArea(M.footprint, home: 34), 108)
        XCTAssertEqual(M.aboveSafeArea(M.stripFootprint, home: 34), 24)
        XCTAssertEqual(M.aboveSafeArea(M.footprint, home: 0), 142, "a Home button phone: all of it")
        XCTAssertEqual(M.navSingleWidth, 48)
        XCTAssertEqual(M.navPairWidth, 96)
        XCTAssertEqual([M.stripHeight, M.stripFontSize, M.stripSidePadding, M.stripMaxWidth], [20, 13, 10, 260])
        XCTAssertEqual(M.stripHitOutset, 12, "20 + 2 * 12 = the 44 pt hit area")
        XCTAssertEqual(M.hitOutset, 0, "48 is already past the 44 pt hit area")
        XCTAssertGreaterThanOrEqual(M.gap, 2 * M.hitOutset, "the rows' hit areas never overlap")
        XCTAssertEqual([M.endGlyphSlot, M.endInset], [24, 12], "concentric: a 24 slot 12 in from a 48 pill's end")
        XCTAssertEqual(M.barHeight / 2 - M.endInset, M.endGlyphSlot / 2, "inner radius = outer - inset")
        XCTAssertEqual(M.barHeight - 2 * M.litInset, 40, "the lit segment")
        XCTAssertGreaterThanOrEqual(M.minTapTarget, 44)
        XCTAssertEqual([M.margin, M.gap, M.topPadding, M.barHeight, M.litInset, M.stripHeight]
                           .map { $0.truncatingRemainder(dividingBy: M.unit) },
                       Array(repeating: 0, count: 6), "every size is a multiple of the unit")
    }

    // MARK: Layout

    func testExpandedWidthsAtEveryPhone() {
        // Row 1 less the margins and Listen's disc and gap: 351 - 46 on the SE, less ‹ › and a gap with arrows.
        for (width, both, none) in [(375.0, 191.0, 295.0), (393, 209, 313), (430, 246, 350)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, back: true, forward: true).field.rect.width, both)
            XCTAssertEqual(layout(.browse, width: w, back: true).field.rect.width, both, "‹ alone still shows the pair: › dimmed")
            XCTAssertEqual(layout(.browse, width: w, forward: true).field.rect.width, both, "› alone: ‹ dimmed")
            XCTAssertEqual(layout(.library, width: w, back: true).field.rect.width, none, "no arrows outside the Browser")
            XCTAssertEqual(layout(.browse, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, w - 2 * M.margin, "the pill alone, margin to margin")
            XCTAssertEqual(layout(.settings, width: w).field.rect.width, none, "Search Settings as wide as Search Library")
            let segment = layout(.settings, width: w).pill.rect.width / CGFloat(ChromeDestination.allCases.count)
            XCTAssertGreaterThanOrEqual(segment, M.minTapTarget, "each of the pill's equal segments is a tap target at \(w)")
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
                XCTAssertEqual(l.field.rect.minX, M.margin, "the field starts at the left margin: \(tag)")
                XCTAssertEqual(l.cancel.rect.maxX, width - M.margin, "Cancel ends at the right margin: \(tag)")
                XCTAssertEqual(l.cancel.rect.width, M.cancelWidth, tag)
                XCTAssertEqual(l.cancel.rect.height, M.barHeight, tag)
                XCTAssertEqual(l.cancel.rect.minX - l.field.rect.maxX, M.rowGap, tag)
                XCTAssertEqual(l.field.rect.width, width - 2 * M.margin - M.rowGap - M.cancelWidth, tag)
                // On the keyboard, not dipped into the home indicator's strip: the row ends at the box's bottom.
                XCTAssertEqual(l.field.rect.maxY, M.footprint, "the row sits on the keyboard: \(tag)")
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
        let neither = layout(.browse)
        XCTAssertFalse(neither.nav.isShown, "a new page has nothing to go back or forward to")
        XCTAssertFalse(layout(.browse, back: false, forward: false).nav.isShown)
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
        XCTAssertEqual(M.margin, 12)
        for width in [375.0, 393, 402, 430, 440, 744, 1024].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                let l = layout(destination, width: width)
                let tag = "\(destination) at \(width)"
                XCTAssertEqual(l.pill.rect.minX, M.margin, tag)
                XCTAssertEqual(l.pill.rect.maxX, width - M.margin, tag)
                XCTAssertEqual(l.field.rect.minX, l.pill.rect.minX, "row 1 starts where row 2 does, \(tag)")
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
                        XCTAssertEqual(piece.rect.height, M.barHeight, tag)
                        XCTAssertGreaterThanOrEqual(piece.rect.width + 2 * M.hitOutset, M.minTapTarget, "a 44 pt hit area with the outset: \(tag)")
                        XCTAssertGreaterThanOrEqual(piece.rect.minX, M.margin - 0.01, tag)
                        XCTAssertLessThanOrEqual(piece.rect.maxX, width - M.margin + 0.01, tag)
                        XCTAssertEqual(piece.radius, M.barHeight / 2, "capsule \(tag)")
                    }
                    for (i, a) in shown.enumerated() {
                        for b in shown[(i + 1)...] where abs(a.rect.minY - b.rect.minY) < M.barHeight / 2 {
                            let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
                            XCTAssertGreaterThanOrEqual(gap, M.rowGap - 0.01, tag)
                        }
                    }
                    // Every hit area (the glass and `hitOutset` round it) is 44 tall and overlaps no other.
                    let hits = shown.map { $0.rect.insetBy(dx: -M.hitOutset, dy: -M.hitOutset) }
                    for (i, a) in hits.enumerated() {
                        XCTAssertEqual(a.height, max(M.minTapTarget, M.barHeight), tag)
                        for b in hits[(i + 1)...] {
                            XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).width * a.intersection(b).height < 0.01, "hit areas overlap: \(tag)")
                        }
                    }
                }
            }
        }
    }

    func testExpandedIsTwoRowsLowInTheBox() {
        let browse = layout(.browse, back: true, forward: true)
        XCTAssertEqual(browse.field.rect.minY + M.barHeight + M.gap, browse.pill.rect.minY, "row 1 over row 2")
        XCTAssertEqual(browse.nav.rect.width, M.navPairWidth)
        XCTAssertEqual(browse.top, browse.field.rect.minY)
        XCTAssertEqual(browse.field.rect.minY, M.topPadding + 34, "the room above row 1 is the home strip the rows reach into")
        XCTAssertEqual(browse.pill.rect.maxY, M.footprint + 34 - M.edgeClearance, "row 2 ends 14 above the screen's edge")
        let se = ChromeLayout(width: 375, state: { var s = ChromeState(destination: .library); s.homeInset = 0; return s }())
        XCTAssertEqual(se.pill.rect.maxY, M.footprint - M.edgeClearance, "with a Home button: 14 above the edge too")
        XCTAssertEqual(se.top, M.topPadding)
    }

    /// The fold's steps: two rows, then one (row 2 gone, row 1 in its place), then the strip.
    func testFoldingGoesTwoRowsThenOneThenTheStrip() {
        let expanded = layout(.browse, progress: 0, back: true)
        let one = layout(.browse, progress: 0.5, back: true)
        let folded = layout(.browse, progress: 1, back: true)
        XCTAssertFalse(expanded.strip.isShown)
        XCTAssertFalse(one.pill.isShown, "one row: row 2 gone")
        XCTAssertTrue(one.field.isShown && one.nav.isShown && one.listen.isShown)
        XCTAssertFalse(one.strip.isShown)
        XCTAssertEqual(one.field.rect, expanded.field.rect.offsetBy(dx: 0, dy: M.barHeight + M.gap), "row 1 drops into row 2's place")
        XCTAssertEqual(one.listen.rect, expanded.listen.rect.offsetBy(dx: 0, dy: M.barHeight + M.gap), "Listen with it")
        XCTAssertEqual(one.field.rect.minY, expanded.pill.rect.minY)
        XCTAssertEqual(one.top, expanded.pill.rect.minY)
        XCTAssertEqual([folded.pill, folded.field, folded.nav, folded.cancel, folded.listen].map(\.isShown),
                       Array(repeating: false, count: 5), "folded: nothing but the strip")
        XCTAssertTrue(folded.strip.isShown)
        XCTAssertEqual(folded.stripOpacity, 1)
        let first = layout(.browse, progress: 0.2, back: true)
        XCTAssertLessThan(first.pill.rect.width, expanded.pill.rect.width, "row 2 shrinks away")
        XCTAssertGreaterThan(first.field.rect.minY, expanded.field.rect.minY, "while row 1 drops")
        XCTAssertEqual(first.field.rect.width, expanded.field.rect.width, "row 1 keeps its size in the first step")
        var last: CGFloat = -1
        for step in 0...20 {
            let o = layout(.browse, progress: CGFloat(step) / 20).stripOpacity
            XCTAssertGreaterThanOrEqual(o, last, "the strip only comes up as the rows fold")
            last = o
        }
    }

    /// The strip at the two phones that matter (the 17 Pro's 402, the SE's 375): a 20 pt text box as wide
    /// as its name (to 260), centred, ending 14 above the screen's edge, a 44 pt hit area, nothing else on screen.
    func testTheStripIsTextAboveTheHomeIndicatorWithA44HitAreaAndTheRowsAreGone() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for (text, expected) in [(0.0, 20.0), (60.0, 80), (110, 130), (300, 260)] {
                    let stripWidth = M.stripWidth(forTextWidth: CGFloat(text))
                    XCTAssertEqual(stripWidth, CGFloat(expected), "\(text) pt of title")
                    let l = ChromeLayout(width: width, state: ChromeState(destination: destination, progress: 1,
                                                                          canGoBack: true, canGoForward: true, stripWidth: stripWidth))
                    let tag = "\(width) \(destination) \(text)"
                    XCTAssertTrue(l.strip.isShown, tag)
                    XCTAssertEqual(l.strip.rect.height, 20, tag)
                    XCTAssertEqual(l.strip.rect.width, stripWidth, tag)
                    XCTAssertEqual(l.strip.rect.midX, width / 2, tag)
                    XCTAssertEqual(l.strip.rect.maxY, M.footprint + 34 - M.edgeClearance, "edgeClearance above the screen's edge: \(tag)")
                    XCTAssertEqual(M.footprint + 34 - l.strip.rect.midY, 44, "centred 44 above the edge: \(tag)")
                    let hit = l.strip.rect.insetBy(dx: 0, dy: -M.stripHitOutset)
                    XCTAssertEqual(hit.height, 44, tag)
                    XCTAssertEqual(l.top, l.strip.rect.minY, "nothing else is on screen: \(tag)")
                }
            }
        }
    }

    func testTheStripIsOnlyThereFoldedAndNeverTypingOrEditing() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            XCTAssertFalse(layout(.browse, width: width, progress: 0).strip.isShown, "expanded")
            XCTAssertFalse(layout(.browse, width: width, progress: 0.5).strip.isShown, "one row")
            XCTAssertFalse(layout(.library, width: width, progress: 1, keyboard: true).strip.isShown, "typing")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .library, progress: 1, editing: true)).strip.isShown, "Edit")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 1, fullScreen: true)).strip.isShown, "full screen")
        }
    }

    func testBrowseArrowsDropForANewPageAndOutsideTheBrowser() {
        XCTAssertFalse(layout(.browse).nav.isShown, "a new page has neither arrow")
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
        XCTAssertTrue(chrome.isCollapsed)
        scroll(chrome, to: [200])
        XCTAssertEqual(chrome.progress, 1, "clamped: the strip")
        scroll(chrome, to: [180])
        XCTAssertEqual(chrome.progress, 1, "a short scroll up gives nothing back")
        scroll(chrome, to: [175])
        XCTAssertEqual(chrome.progress, 0, "24 pt up brings both rows back")
        scroll(chrome, to: [195, 190, 200])
        XCTAssertEqual(chrome.progress, 30 / ChromeScroll.travel, accuracy: 0.001, "5 pt up between two scrolls down reveals nothing")
        XCTAssertFalse(chrome.isCollapsed)
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
        XCTAssertEqual(down.progress, 1, "a second step stopped partway ends at the strip")
        let reverse = ChromeScroll()
        reverse.anchor(at: 10)
        scroll(reverse, to: [40, 30, 20, 12, 10])
        reverse.settle()
        XCTAssertEqual(reverse.progress, 0, "turning back 30 pt brings both rows back")
        XCTAssertEqual([0, 0.1, 0.5, 0.6, 1].map { ChromeScroll.stepEnd(CGFloat($0)) }, [0, 0.5, 0.5, 1, 1])
        XCTAssertEqual([0, 0.2, 0.5, 0.74, 0.8, 1].map { ChromeScroll.step(CGFloat($0)) }, [0, 0, 1, 1, 2, 2])
    }

    /// The strip's tap brings both rows back for a short scroll down only: past `refoldGrace` they fold
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
            XCTAssertTrue(chrome.isCollapsed)
        }
    }

    @MainActor
    func testAHeldDestinationNeverFoldsAndLeavingItStartsExpanded() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [130])
        XCTAssertTrue(chrome.isCollapsed, "a Library scrolled down")
        chrome.holdsExpanded = true
        XCTAssertFalse(chrome.isCollapsed, "coming to a held screen (Pages mode, Edit) from a folded Library: expanded")
        chrome.anchor(at: 10)
        scroll(chrome, to: [60, 120, 200, 300])
        XCTAssertEqual(chrome.progress, 0)
        XCTAssertFalse(chrome.isCollapsed)
        chrome.holdsExpanded = false
        chrome.reset()
        scroll(chrome, to: [130])
        XCTAssertTrue(chrome.isCollapsed, "other destinations fold again")
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
