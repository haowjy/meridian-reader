import XCTest
@testable import MeridianReader

/// The compact chrome's rules: its state (`ChromeState`), where every piece sits (`ChromeLayout`,
/// checked against the mockups' `width-table.md` and the invariants of `rules.js`) and how scrolling
/// folds it (`ChromeScroll`). Pure values, no screen.
final class ChromeTests: XCTestCase {
    private typealias M = ChromeMetrics

    private func layout(_ destination: ChromeDestination, width: CGFloat = 393, progress: CGFloat = 0, played: Bool = false,
                        back: Bool = false, forward: Bool = false, keyboard: Bool = false) -> ChromeLayout {
        ChromeLayout(width: width, state: ChromeState(destination: destination, progress: progress, played: played,
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

    func testListenHoldsTheChromeExpandedWhateverTheScroll() {
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).collapse, 0)
        XCTAssertEqual(ChromeState(destination: .library, progress: 1).collapse, 1)
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).fold, 0)
    }

    func testEditKeepsBothRowsAndListenNeverShowsTheStripWhateverTheScroll() {
        func state(_ destination: ChromeDestination, editing: Bool = false) -> ChromeState {
            ChromeState(destination: destination, progress: 1, played: true, editing: editing)
        }
        let scrolled = ChromeLayout(width: 393, state: state(.browse))
        let edit = ChromeLayout(width: 393, state: state(.library, editing: true))
        let listen = ChromeLayout(width: 393, state: state(.reader))
        XCTAssertTrue(scrolled.strip.isShown)
        XCTAssertFalse(scrolled.pill.isShown, "scrolled: the rows are the strip")
        XCTAssertFalse(edit.strip.isShown, "Edit: row 2 stays")
        XCTAssertTrue(edit.editBar.isShown)
        XCTAssertFalse(listen.strip.isShown, "Listen never folds")
        XCTAssertTrue(listen.pill.isShown && listen.field.isShown)
        XCTAssertEqual(listen.field.rect.minY + M.card + M.gap, listen.pill.rect.minY)
    }

    /// Browse reader mode: the Listen control is a bar-sized disc at the end of row 1 and the field gives it
    /// its room; any other state has no control and the field runs to the margin.
    func testBrowseReaderModeHasTheListenDiscAtTheEndOfRowOneAndTheFieldYieldsToIt() {
        let width: CGFloat = 393
        let page = ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 0, played: true))
        let reader = ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 0, played: true, readerMode: true))
        XCTAssertFalse(page.listen.isShown)
        XCTAssertTrue(reader.listen.isShown)
        XCTAssertEqual(reader.listen.rect.width, M.barHeight)
        XCTAssertEqual(reader.listen.rect.height, M.barHeight)
        XCTAssertEqual(reader.listen.rect.maxX, width - M.margin)
        XCTAssertEqual(reader.listen.rect.minY, reader.field.rect.minY)
        XCTAssertEqual(reader.field.rect.maxX + M.rowGap, reader.listen.rect.minX)
        XCTAssertEqual(page.field.rect.maxX, width - M.margin, "the field runs to the margin without the control")
        let library = ChromeLayout(width: width, state: ChromeState(destination: .library, progress: 0, played: true, readerMode: true))
        XCTAssertFalse(library.listen.isShown, "the Library's Listen field is the field itself")
    }

    // MARK: Tokens

    func testOneBarHeightDerivesEveryFootprintAndWidth() {
        XCTAssertEqual(M.barHeight, 36)
        XCTAssertEqual(M.edgeClearance, 14, "the bottom row ends 14 above the screen's edge")
        XCTAssertEqual(M.footprint, 98, "4 + 36 + 8 + 36 + 14, from the screen's edge")
        XCTAssertEqual(M.collapsedFootprint, 54, "one row: the keyboard's and the fold's first step")
        XCTAssertEqual(M.stripFootprint, 38, "the strip: 4 + 20 + 14")
        XCTAssertEqual(M.readerFootprint, 202)
        XCTAssertEqual([M.footprint(step: 0), M.footprint(step: 1), M.footprint(step: 2)], [98, 54, 38])
        XCTAssertEqual(M.aboveSafeArea(M.footprint, home: 34), 64)
        XCTAssertEqual(M.aboveSafeArea(M.stripFootprint, home: 34), 4)
        XCTAssertEqual(M.aboveSafeArea(M.footprint, home: 0), 98, "a Home button phone: all of it")
        XCTAssertEqual(M.navSingleWidth, 36)
        XCTAssertEqual(M.navPairWidth, 72)
        XCTAssertEqual([M.stripHeight, M.stripFontSize, M.stripSidePadding, M.stripMaxWidth], [20, 13, 10, 260])
        XCTAssertEqual(M.stripHitOutset, 12, "20 + 2 * 12 = the 44 pt hit area")
        XCTAssertEqual(M.hitOutset, 4, "36 + 2 * 4 = the 44 pt hit area")
        XCTAssertEqual(M.gap, 2 * M.hitOutset, "the rows' hit areas meet in the gap and never overlap")
        XCTAssertEqual([M.endGlyphSlot, M.endInset], [24, 6], "concentric: a 24 slot 6 in from a 36 pill's end")
        XCTAssertEqual(M.barHeight / 2 - M.endInset, M.endGlyphSlot / 2, "inner radius = outer - inset")
        XCTAssertEqual(M.barHeight - 2 * M.litInset, 28, "the lit segment")
        XCTAssertEqual(M.cardRadius, 24, "Listen's card keeps its corners")
        XCTAssertGreaterThanOrEqual(M.minTapTarget, 44)
        XCTAssertEqual([M.margin, M.gap, M.topPadding, M.barHeight, M.litInset, M.stripHeight].map { $0.truncatingRemainder(dividingBy: M.unit) },
                       Array(repeating: 0, count: 6), "every size is a multiple of the unit")
    }

    // MARK: Layout: widths from width-table.md

    func testExpandedWidthsAtEveryPhone() {
        for (width, both, none) in [(375.0, 269.0, 351.0), (393, 287, 369), (430, 324, 406)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, back: true, forward: true).field.rect.width, both)
            XCTAssertEqual(layout(.browse, width: w, back: true).field.rect.width, both, "‹ alone still shows the pair: › dimmed")
            XCTAssertEqual(layout(.browse, width: w, forward: true).field.rect.width, both, "› alone: ‹ dimmed")
            XCTAssertEqual(layout(.library, width: w, back: true).field.rect.width, none, "no arrows outside the Browser")
            XCTAssertEqual(layout(.browse, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, 235, "row 2, nothing played: ▶'s slot stays reserved and empty, and the pill is the SE's 235 on every phone")
            XCTAssertEqual(layout(.library, width: w, played: true).pill.rect.width, 235, "[pill][▶][⋯]")
        }
    }

    /// Typing: the field and Cancel only (no pill, ▶, ⋯ or arrows), margin to margin on every phone:
    /// the field from the left margin, Cancel (a word, `cancelWidth`) ending at the right margin, one gap
    /// between, at the bottom row's y, whatever was played or where the arrows were. Not the fixed 351 block.
    func testTypingIsTheFieldAndCancelMarginToMargin() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            for destination in [ChromeDestination.browse, .library] {
                for played in [false, true] {
                    let l = layout(destination, width: width, played: played, back: true, forward: true, keyboard: true)
                    let rest = layout(destination, width: width, played: played)
                    let tag = "\(width) \(destination) played \(played)"
                    XCTAssertFalse(l.pill.isShown, tag)
                    XCTAssertFalse(l.play.isShown, tag)
                    XCTAssertFalse(l.nav.isShown && l.navShowsBack, tag)
                    XCTAssertTrue(l.field.isShown && l.more.isShown, tag)
                    XCTAssertEqual(l.field.rect.minX, M.margin, "the field starts at the left margin: \(tag)")
                    XCTAssertEqual(l.more.rect.maxX, width - M.margin, "Cancel ends at the right margin: \(tag)")
                    XCTAssertEqual(l.more.rect.width, M.cancelWidth, tag)
                    XCTAssertEqual(l.more.rect.height, M.barHeight, tag)
                    XCTAssertEqual(l.more.rect.minX - l.field.rect.maxX, M.rowGap, tag)
                    XCTAssertEqual(l.field.rect.width, width - 2 * M.margin - M.rowGap - M.cancelWidth, tag)
                    // On the keyboard, not dipped into the home indicator's strip: the row ends at the box's bottom.
                    XCTAssertEqual(l.field.rect.maxY, M.readerFootprint, "the row sits on the keyboard: \(tag)")
                    XCTAssertEqual(l.more.rect.minY, l.field.rect.minY, tag)
                    XCTAssertLessThan(l.field.rect.minY, rest.more.rect.minY, "above the resting row 2, which dips: \(tag)")
                }
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

    func testPlayStaysAtTheWidthTablesX() {
        for (width, x) in [(375.0, 281.0), (393, 299), (430, 336)] {  // margin to margin: ▶ at width − 12 − 82
            XCTAssertEqual(layout(.library, width: CGFloat(width), played: true).play.rect.minX, x, "▶ at \(width)")
        }
    }

    func testTheRowIsAPillAndTwoDiscsWithOneEvenGap() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let l = layout(.library, width: width, played: true)
            XCTAssertGreaterThanOrEqual(l.play.rect.minX - l.pill.rect.maxX, M.rowGap, "pill, gap, ▶ at \(width)")
            XCTAssertEqual(l.play.rect.maxX + M.rowGap, l.more.rect.minX, "▶, gap, ⋯ at \(width)")
            XCTAssertEqual(l.play.rect.width, M.barHeight)
            XCTAssertEqual(l.more.rect.width, M.barHeight)
            XCTAssertEqual(l.pill.rect.width, l.expandedPillWidth)
            XCTAssertGreaterThanOrEqual(l.expandedPillWidth / M.barHeight, 4.8, "a long capsule, not a fat one, at \(width)")
        }
        XCTAssertEqual(layout(.library, width: 402, played: true).expandedPillWidth, 235)
    }

    func testPlayKeepsItsSlotAndTheMoreEndsTheCentredRow() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases where destination != .reader {
                let expanded = layout(destination, width: width, played: true)
                XCTAssertGreaterThanOrEqual(expanded.play.rect.minX - expanded.pill.rect.maxX, M.rowGap, "[pill][▶]")
                XCTAssertEqual(expanded.play.rect.maxX + M.rowGap, expanded.more.rect.minX, "[▶][⋯]")
                XCTAssertEqual(expanded.more.rect.maxX, width - M.margin, "⋯ ends the row at the margin")
            }
        }
        XCTAssertFalse(layout(.library).play.isShown, "no ▶ before anything has played")
    }

    func testListenHasNoPlayDiscAndItsSlotStaysEmptyAtEveryFold() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let library = layout(.library, width: width, played: true)
            for progress in [0.0, 1.0] {
                let l = layout(.reader, width: width, progress: CGFloat(progress), played: true)
                XCTAssertFalse(l.play.isShown, "Listen's card has the play button at \(width)")
                XCTAssertFalse(l.strip.isShown, "Listen never folds")
                XCTAssertEqual(l.pill.rect, library.pill.rect, "the pill is the Library's, not wider, at \(width)")
                XCTAssertEqual(l.more.rect, library.more.rect)
                XCTAssertGreaterThanOrEqual(library.play.rect.minX - l.pill.rect.maxX, M.rowGap, "▶'s slot stays empty between the pill and ⋯")
                XCTAssertEqual(library.play.rect.maxX + M.rowGap, l.more.rect.minX)
                XCTAssertEqual(l.field.rect.height, M.card, "the card stays")
            }
        }
        XCTAssertTrue(layout(.library, played: true).play.isShown, "▶ stays on the other destinations")
    }

    /// One pill, one width, one x on every destination and state (▶ or not): tabs never move or resize it.
    func testThePillAndMoreNeverMoveOrResizeAcrossDestinationsAndStates() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let reference = layout(.library, width: width, played: true)
            for destination in ChromeDestination.allCases {
                for played in [false, true] {
                    for back in [false, true] {
                        let l = layout(destination, width: width, played: played, back: back, forward: back)
                        XCTAssertEqual(l.pill.rect, reference.pill.rect, "\(destination) played \(played) at \(width)")
                        XCTAssertEqual(l.more.rect, reference.more.rect)
                        XCTAssertEqual(l.expandedPillWidth, reference.expandedPillWidth)
                    }
                }
            }
        }
        XCTAssertEqual(layout(.reader, width: 402).expandedPillWidth, 235)
        XCTAssertEqual(layout(.library, width: 375).expandedPillWidth, 235)
    }

    /// Both rows share the margins as their edges on every width (Jimmy: "the 2 bars should be the same
    /// length"): the pill is one fixed width at the left, ▶ and ⋯ end the row, the gap after the pill grows.
    func testBothRowsShareTheSameEdgesOnEveryWidth() {
        XCTAssertEqual(M.pillWidth, 235)
        XCTAssertEqual(M.bottomRowWidth, 327, "the pill, ▶ and ⋯ with their gaps: room to spare on the SE")
        XCTAssertEqual(M.margin, 12)
        for width in [375.0, 393, 402, 430, 440, 744, 1024].map({ CGFloat($0) }) {
            for played in [false, true] {
                for destination in ChromeDestination.allCases where destination != .reader {
                    let l = layout(destination, width: width, played: played)
                    let tag = "\(destination) played \(played) at \(width)"
                    XCTAssertEqual(l.pill.rect.minX, M.margin, tag)
                    XCTAssertEqual(l.more.rect.maxX, width - M.margin, tag)
                    XCTAssertEqual(l.field.rect.minX, l.pill.rect.minX, "row 1 starts where row 2 does, \(tag)")
                    XCTAssertEqual(l.field.rect.maxX, l.more.rect.maxX, "row 1 ends where row 2 does, \(tag)")
                    XCTAssertEqual(l.pill.rect.width, M.pillWidth, tag)
                    XCTAssertEqual(l.more.rect.minX - l.pill.rect.maxX, width - 2 * M.margin - M.pillWidth - M.barHeight, tag)
                }
            }
        }
    }

    func testEveryPieceIsAsTallAsTheBarWideEnoughToTapAndInsideTheMargins() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for played in [false, true] {
                    for (progress, keyboard) in [(0.0, false), (1.0, false), (0.0, true)] where !(keyboard && destination == .reader) {
                        let l = layout(destination, width: width, progress: CGFloat(progress), played: played, back: true, forward: true, keyboard: keyboard)
                        let tag = "\(width) \(destination) played \(played) progress \(progress) keyboard \(keyboard)"
                        let shown = [l.pill, l.field, l.nav, l.play, l.more].filter(\.isShown)
                        for piece in shown {
                            let isCard = destination == .reader && piece == l.field
                            XCTAssertEqual(piece.rect.height, isCard ? M.card : M.barHeight, tag)
                            XCTAssertGreaterThanOrEqual(piece.rect.width + 2 * M.hitOutset, M.minTapTarget, "a 44 pt hit area with the outset: \(tag)")
                            XCTAssertGreaterThanOrEqual(piece.rect.minX, M.margin - 0.01, tag)
                            XCTAssertLessThanOrEqual(piece.rect.maxX, width - M.margin + 0.01, tag)
                            XCTAssertEqual(piece.radius, isCard ? M.cardRadius : M.barHeight / 2, "capsule \(tag)")
                        }
                        for (i, a) in shown.enumerated() {
                            for b in shown[(i + 1)...] where abs(a.rect.minY - b.rect.minY) < M.barHeight / 2 {
                                let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
                                XCTAssertGreaterThanOrEqual(gap, M.rowGap - 0.01, tag)
                            }
                        }
                        // Every hit area (the glass and `hitOutset` round it) is 44 tall and overlaps no other.
                        let hits = [l.field, l.nav, l.play, l.more].filter { $0.isShown && $0.rect.height == M.barHeight }
                            .map { $0.rect.insetBy(dx: -M.hitOutset, dy: -M.hitOutset) }
                        for (i, a) in hits.enumerated() {
                            XCTAssertEqual(a.height, M.minTapTarget, tag)
                            for b in hits[(i + 1)...] {
                                XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).width * a.intersection(b).height < 0.01, "hit areas overlap: \(tag)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testExpandedIsTwoRowsAndTheReaderCardSitsOneGapAboveRowTwo() {
        let browse = layout(.browse, back: true, forward: true)
        XCTAssertEqual(browse.field.rect.minY + M.barHeight + M.gap, browse.pill.rect.minY, "row 1 over row 2")
        XCTAssertEqual(browse.nav.rect.width, M.navPairWidth)
        XCTAssertEqual(browse.top, browse.field.rect.minY)
        let reader = layout(.reader, played: true)
        XCTAssertEqual(reader.field.rect.height, M.card)
        XCTAssertEqual(reader.field.rect.maxY + M.gap, reader.pill.rect.minY)
        XCTAssertEqual(reader.field.rect.minY, M.topPadding + 34, "the card's room above it is the home strip the rows reach into")
        XCTAssertEqual(browse.pill.rect.maxY, M.readerFootprint + 34 - M.edgeClearance, "row 2 ends 14 above the screen's edge")
        let se = ChromeLayout(width: 375, state: { var s = ChromeState(destination: .library); s.homeInset = 0; return s }())
        XCTAssertEqual(se.pill.rect.maxY, M.readerFootprint - M.edgeClearance, "with a Home button: 14 above the edge too")
    }

    /// The fold's steps: two rows, then one (row 2 gone, row 1 in its place), then the strip.
    func testFoldingGoesTwoRowsThenOneThenTheStrip() {
        let expanded = layout(.browse, progress: 0, played: true, back: true)
        let one = layout(.browse, progress: 0.5, played: true, back: true)
        let folded = layout(.browse, progress: 1, played: true, back: true)
        XCTAssertFalse(expanded.strip.isShown)
        XCTAssertEqual([one.pill, one.play, one.more].map(\.isShown), [false, false, false], "one row: row 2 gone")
        XCTAssertTrue(one.field.isShown && one.nav.isShown)
        XCTAssertFalse(one.strip.isShown)
        XCTAssertEqual(one.field.rect, expanded.field.rect.offsetBy(dx: 0, dy: M.barHeight + M.gap), "row 1 drops into row 2's place")
        XCTAssertEqual(one.field.rect.minY, expanded.pill.rect.minY)
        XCTAssertEqual(one.top, expanded.pill.rect.minY)
        XCTAssertEqual([folded.pill, folded.field, folded.nav, folded.play, folded.more, folded.listen].map(\.isShown),
                       Array(repeating: false, count: 6), "folded: nothing but the strip")
        XCTAssertTrue(folded.strip.isShown)
        XCTAssertEqual(folded.stripOpacity, 1)
        let first = layout(.browse, progress: 0.2, played: true, back: true)
        XCTAssertLessThan(first.pill.rect.width, expanded.pill.rect.width, "row 2 shrinks away")
        XCTAssertGreaterThan(first.field.rect.minY, expanded.field.rect.minY, "while row 1 drops")
        XCTAssertEqual(first.field.rect.width, expanded.field.rect.width, "row 1 keeps its size in the first step")
        var last: CGFloat = -1
        for step in 0...20 {
            let o = layout(.browse, progress: CGFloat(step) / 20, played: true).stripOpacity
            XCTAssertGreaterThanOrEqual(o, last, "the strip only comes up as the rows fold")
            last = o
        }
    }

    /// The strip at the two phones that matter (the 17 Pro's 402, the SE's 375): a 20 pt text box as wide
    /// as its name (to 260), centred, ending 14 above the screen's edge, a 44 pt hit area, nothing else on screen.
    func testTheStripIsTextAboveTheHomeIndicatorWithA44HitAreaAndTheRowsAreGone() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            for destination in [ChromeDestination.browse, .library] {
                for (text, expected) in [(0.0, 20.0), (60.0, 80), (110, 130), (300, 260)] {
                    let stripWidth = M.stripWidth(forTextWidth: CGFloat(text))
                    XCTAssertEqual(stripWidth, CGFloat(expected), "\(text) pt of title")
                    let l = ChromeLayout(width: width, state: ChromeState(destination: destination, progress: 1, played: true,
                                                                          canGoBack: true, canGoForward: true, stripWidth: stripWidth))
                    let tag = "\(width) \(destination) \(text)"
                    XCTAssertTrue(l.strip.isShown, tag)
                    XCTAssertEqual(l.strip.rect.height, 20, tag)
                    XCTAssertEqual(l.strip.rect.width, stripWidth, tag)
                    XCTAssertEqual(l.strip.rect.midX, width / 2, tag)
                    XCTAssertEqual(l.strip.rect.maxY, M.readerFootprint + 34 - M.edgeClearance, "14 above the screen's edge: \(tag)")
                    XCTAssertEqual(M.readerFootprint + 34 - l.strip.rect.midY, 24, "centred 24 above the edge: \(tag)")
                    let hit = l.strip.rect.insetBy(dx: 0, dy: -M.stripHitOutset)
                    XCTAssertEqual(hit.height, 44, tag)
                    XCTAssertEqual(l.top, l.strip.rect.minY, "nothing else is on screen: \(tag)")
                }
            }
        }
    }

    func testTheStripIsOnlyThereFoldedAndNeverTypingOrOnListenOrEditing() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            XCTAssertFalse(layout(.browse, width: width, progress: 0).strip.isShown, "expanded")
            XCTAssertFalse(layout(.browse, width: width, progress: 0.5).strip.isShown, "one row")
            XCTAssertFalse(layout(.library, width: width, progress: 1, keyboard: true).strip.isShown, "typing")
            XCTAssertFalse(layout(.reader, width: width, progress: 1).strip.isShown, "Listen")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .library, progress: 1, editing: true)).strip.isShown, "Edit")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 1, fullScreen: true)).strip.isShown, "full screen")
        }
    }

    func testBrowseArrowsDropForANewPageAndOutsideTheBrowser() {
        XCTAssertFalse(layout(.browse).nav.isShown, "a new page has neither arrow")
        XCTAssertFalse(layout(.library, back: true).nav.isShown, "only the Browser has arrows")
    }

    func testEditBarReplacesRowTwoAndFullScreenShowsNothing() {
        let edit = ChromeLayout(width: 393, state: ChromeState(destination: .library, played: true, editing: true))
        XCTAssertTrue(edit.editBar.isShown)
        XCTAssertEqual([edit.pill, edit.play, edit.more].map(\.isShown), [false, false, false])
        let full = ChromeLayout(width: 393, state: ChromeState(destination: .reader, fullScreen: true, played: true))
        XCTAssertEqual([full.pill, full.field, full.nav, full.play, full.more, full.editBar].map(\.isShown), Array(repeating: false, count: 6))
        XCTAssertNil(full.top)
    }

    // MARK: Scroll

    @MainActor
    private func scroll(_ chrome: ChromeScroll, to offsets: [CGFloat]) { offsets.forEach { chrome.scrolled(to: $0) } }

    @MainActor
    func testProgressFollowsTheFingerDownSixtyPointsAStepAndNeverBackUp() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [70])
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "60 pt: one row")
        XCTAssertTrue(chrome.isCollapsed)
        scroll(chrome, to: [200])
        XCTAssertEqual(chrome.progress, 1, "clamped: the strip")
        scroll(chrome, to: [70])
        XCTAssertEqual(chrome.progress, 1, "scrolling up gives no row back")
        scroll(chrome, to: [20])
        XCTAssertEqual(chrome.progress, 1, "not even most of the way up")
        scroll(chrome, to: [3])
        XCTAssertEqual(chrome.progress, 0, "only the very top expands it")
        XCTAssertFalse(chrome.isCollapsed)
    }

    @MainActor
    func testAFoldStoppedBetweenStepsFinishesItsStepAndReverseScrollNeverReExpands() {
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
        XCTAssertEqual(reverse.progress, 0.5, "a step that turns back still ends folded")
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
        XCTAssertEqual(chrome.progress, 6 / ChromeScroll.travel, accuracy: 0.001, "and up never unfolds")
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
        XCTAssertFalse(chrome.isCollapsed, "coming to Listen from a folded Library: expanded")
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
