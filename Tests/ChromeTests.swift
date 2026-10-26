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

    func testReaderModeAndEditHoldTheChromeExpandedAndTheKeyboardFoldsIt() {
        var state = ChromeState(destination: .browse, progress: 1)
        XCTAssertEqual(state.collapse, 1)
        state.readerMode = true
        XCTAssertEqual(state.collapse, 0)
        state = ChromeState(destination: .library, progress: 1, editing: true)
        XCTAssertEqual(state.collapse, 0)
        XCTAssertEqual(ChromeState(destination: .library, keyboard: true).fold, 1)
    }

    func testListenHoldsTheChromeExpandedWhateverTheScroll() {
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).collapse, 0)
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).fold, 0)
        XCTAssertEqual(ChromeState(destination: .library, progress: 1).collapse, 1)
    }

    func testReaderModeAndEditKeepTheLayoutExpandedWhateverTheScroll() {
        func state(_ destination: ChromeDestination, readerMode: Bool = false, editing: Bool = false) -> ChromeState {
            ChromeState(destination: destination, progress: 1, played: true, readerMode: readerMode, editing: editing)
        }
        let scrolled = ChromeLayout(width: 393, state: state(.browse)), reader = ChromeLayout(width: 393, state: state(.browse, readerMode: true))
        let edit = ChromeLayout(width: 393, state: state(.library, editing: true))
        XCTAssertEqual(scrolled.fold, 1)
        XCTAssertEqual(reader.fold, 0, "Reader mode: two rows")
        XCTAssertEqual(reader.field.rect.minY + M.barHeight + M.gap, reader.pill.rect.minY)
        XCTAssertEqual(edit.fold, 0, "Edit: row 2 stays")
        XCTAssertTrue(edit.editBar.isShown)
    }

    // MARK: Tokens

    func testOneBarHeightDerivesEveryFootprintAndWidth() {
        XCTAssertEqual(M.barHeight, 48)
        XCTAssertEqual(M.footprint, 116)
        XCTAssertEqual(M.collapsedFootprint, 60)
        XCTAssertEqual(M.navSingleWidth, 48)
        XCTAssertEqual(M.navPairWidth, 96)
        XCTAssertEqual(M.barHeight - 2 * M.litInset, 40, "the lit segment")
        XCTAssertGreaterThanOrEqual(M.minTapTarget, 44)
        XCTAssertEqual([M.margin, M.gap, M.topPadding, M.bottomPadding, M.barHeight, M.litInset].map { $0.truncatingRemainder(dividingBy: M.unit) },
                       Array(repeating: 0, count: 6), "every size is a multiple of the unit")
    }

    // MARK: Layout: widths from width-table.md

    func testExpandedWidthsAtEveryPhone() {
        for (width, both, single, none) in [(375.0, 245.0, 293.0, 351.0), (393, 263, 311, 369), (430, 300, 348, 406)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, back: true, forward: true).field.rect.width, both)
            XCTAssertEqual(layout(.browse, width: w, back: true).field.rect.width, both, "‹ alone still shows the pair: › dimmed")
            XCTAssertEqual(layout(.browse, width: w, forward: true).field.rect.width, both, "› alone: ‹ dimmed")
            XCTAssertEqual(layout(.library, width: w, back: true).field.rect.width, none, "no arrows outside the Browser")
            XCTAssertEqual(layout(.browse, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, none - 116, "row 2, nothing played: ▶'s slot stays reserved and empty, so the pill is the same")
            XCTAssertEqual(layout(.library, width: w, played: true).pill.rect.width, none - 116, "[pill][▶][⋯]")
        }
    }

    func testCollapsedWidthsAtEveryPhone() {
        // (width, Browse with both arrows and nothing played, Browse with ▶, Browse new page with ▶, Library, Library with ▶)
        for (width, browseBoth, browsePlayed, browseNew, library, libraryPlayed) in
            [(375.0, 129.0, 119.0, 177.0, 235.0, 177.0), (393, 147, 137, 195, 253, 195), (430, 184, 126, 232, 290, 232)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, back: true, forward: true).field.rect.width, browseBoth)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, played: true, back: true, forward: true).field.rect.width, browsePlayed)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, played: true).field.rect.width, browseNew)
            XCTAssertEqual(layout(.library, width: w, progress: 1).field.rect.width, library)
            XCTAssertEqual(layout(.library, width: w, progress: 1, played: true).field.rect.width, libraryPlayed)
            XCTAssertEqual(layout(.reader, width: w, progress: 1, played: true).field.rect.width, w - 2 * M.margin, "Listen never folds: its card stays full width")
            XCTAssertEqual(layout(.library, width: w, played: true, keyboard: true).field.rect.width, libraryPlayed, "keyboard: [field][icon][▶][✕]")
            XCTAssertEqual(layout(.browse, width: w, played: true, back: true, forward: true, keyboard: true).field.rect.width, browseNew)
        }
    }

    func testBrowseNeverHidesAnArrowThatWorks() {
        // Went back to the first page: › alone works. It shows, in the pair expanded and alone folded.
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let expanded = layout(.browse, width: width, forward: true)
            XCTAssertTrue(expanded.navShowsBack && expanded.navShowsForward, "the pair, ‹ dimmed, at \(width)")
            XCTAssertEqual(expanded.nav.rect.width, M.navPairWidth)
            let folded = layout(.browse, width: width, progress: 1, forward: true)
            XCTAssertTrue(folded.navShowsForward && !folded.navShowsBack, "folded: › alone at \(width)")
            XCTAssertEqual(folded.nav.rect.width, M.navSingleWidth)
            XCTAssertEqual(folded.nav.rect.maxX + M.rowGap, folded.field.rect.minX)
            let onlyBack = layout(.browse, width: width, progress: 1, back: true)
            XCTAssertTrue(onlyBack.navShowsBack && !onlyBack.navShowsForward, "folded: ‹ alone at \(width)")
        }
        let neither = layout(.browse, progress: 1)
        XCTAssertFalse(neither.nav.isShown, "a new page has nothing to go back or forward to")
        XCTAssertFalse(layout(.browse, back: false, forward: false).nav.isShown)
    }

    func testFoldedArrowsGiveWayToTheFieldForwardFirst() {
        // ‹ › ▶ on the 17 Pro (402) leave the field 88 pt: › goes, ‹ stays (146); the SE (375) keeps ‹ at 119.
        let pro = layout(.browse, width: 402, progress: 1, played: true, back: true, forward: true)
        XCTAssertTrue(pro.navShowsBack && !pro.navShowsForward)
        XCTAssertEqual(pro.field.rect.width, 146)
        XCTAssertGreaterThanOrEqual(pro.field.rect.width, M.minimumField)
        let se = layout(.browse, width: 375, progress: 1, played: true, back: true, forward: true)
        XCTAssertTrue(se.navShowsBack && !se.navShowsForward)
        XCTAssertEqual(se.field.rect.width, 119)
        // Both arrows and no ▶ fit everywhere: [‹ ›][field][icon][⋯].
        for width in [375.0, 402, 430].map({ CGFloat($0) }) {
            let l = layout(.browse, width: width, progress: 1, back: true, forward: true)
            XCTAssertTrue(l.navShowsBack && l.navShowsForward)
            XCTAssertGreaterThanOrEqual(l.field.rect.width, M.minimumField)
        }
        // › alone with ▶ on the SE: it fits (field 135), so it stays.
        XCTAssertTrue(layout(.browse, width: 375, progress: 1, played: true, forward: true).navShowsForward)
    }

    func testPlayStaysAtTheWidthTablesX() {
        for (width, x) in [(375.0, 257.0), (393, 275), (430, 312)] {
            for progress in [0.0, 1] {
                XCTAssertEqual(layout(.library, width: CGFloat(width), progress: CGFloat(progress), played: true).play.rect.minX, x, "▶ at \(width)")
            }
        }
    }

    func testTheRowIsAPillAndTwoDiscsWithOneEvenGap() {
        for width in [375.0, 393, 402, 430].map({ CGFloat($0) }) {
            let l = layout(.library, width: width, played: true)
            XCTAssertEqual(l.pill.rect.maxX + M.rowGap, l.play.rect.minX, "pill, gap, ▶ at \(width)")
            XCTAssertEqual(l.play.rect.maxX + M.rowGap, l.more.rect.minX, "▶, gap, ⋯ at \(width)")
            XCTAssertEqual(l.play.rect.width, M.barHeight)
            XCTAssertEqual(l.more.rect.width, M.barHeight)
            XCTAssertEqual(l.pill.rect.width, l.expandedPillWidth)
            XCTAssertGreaterThanOrEqual(l.expandedPillWidth / M.barHeight, 4.8, "a long capsule, not a fat one, at \(width)")
        }
        XCTAssertEqual(layout(.library, width: 402, played: true).expandedPillWidth, 262)
    }

    func testPlayKeepsItsSlotAndTheIconSitsLeftOfIt() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases where destination != .reader {
                let expanded = layout(destination, width: width, played: true), collapsed = layout(destination, width: width, progress: 1, played: true)
                XCTAssertEqual(expanded.play.rect, collapsed.play.rect, "▶ does not travel")
                XCTAssertEqual(expanded.more.rect, collapsed.more.rect)
                XCTAssertEqual(collapsed.pill.rect.maxX + M.rowGap, collapsed.play.rect.minX, "[icon][▶]")
                XCTAssertEqual(collapsed.play.rect.maxX + M.rowGap, collapsed.more.rect.minX, "[▶][⋯]")
                XCTAssertEqual(expanded.more.rect.maxX, width - M.margin)
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
                XCTAssertEqual(l.fold, 0, "Listen never folds")
                XCTAssertEqual(l.pill.rect, library.pill.rect, "the pill is the Library's, not wider, at \(width)")
                XCTAssertEqual(l.more.rect, library.more.rect)
                XCTAssertEqual(l.pill.rect.maxX + M.rowGap, library.play.rect.minX, "▶'s slot stays empty between the pill and ⋯")
                XCTAssertEqual(library.play.rect.maxX + M.rowGap, l.more.rect.minX)
                XCTAssertEqual(l.field.rect.height, M.card, "the card stays")
            }
        }
        XCTAssertTrue(layout(.library, played: true).play.isShown, "▶ stays on the other destinations")
        XCTAssertTrue(layout(.browse, progress: 1, played: true).play.isShown, "and when folded")
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
        XCTAssertEqual(layout(.reader, width: 402).expandedPillWidth, 262)
        XCTAssertEqual(layout(.library, width: 375).expandedPillWidth, 235)
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
                            XCTAssertGreaterThanOrEqual(piece.rect.width, M.minTapTarget, tag)
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
        XCTAssertEqual(reader.field.rect.minY, M.topPadding, "the box holds the card exactly")
    }

    func testFoldingMixesEveryFrameBetweenTheTwoForms() {
        let a = layout(.browse, progress: 0, played: true, back: true), b = layout(.browse, progress: 1, played: true, back: true)
        let half = layout(.browse, progress: 0.5, played: true, back: true)
        XCTAssertEqual(half.pill.rect.width, (a.pill.rect.width + b.pill.rect.width) / 2, accuracy: 0.001)
        XCTAssertEqual(half.field.rect.minY, (a.field.rect.minY + b.field.rect.minY) / 2, accuracy: 0.001)
        XCTAssertEqual(half.fold, 0.5)
    }

    func testBrowseArrowsDropForANewPageAndGiveWayToAFieldTooNarrow() {
        XCTAssertFalse(layout(.browse).nav.isShown, "a new page has neither arrow")
        XCTAssertFalse(layout(.library, back: true).nav.isShown, "only the Browser has arrows")
        XCTAssertEqual(layout(.browse, width: 320, progress: 1, played: true, back: true, forward: true).nav.rect.width, 0,
                       "folded on a narrow phone with ▶: the field keeps its minimum")
        XCTAssertGreaterThanOrEqual(layout(.browse, width: 320, progress: 1, played: true, back: true, forward: true).field.rect.width, M.minimumField)
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
    func testProgressFollowsTheFingerDownAtNinetyPointsATravelAndNeverBackUp() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [55])
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001)
        scroll(chrome, to: [100])
        XCTAssertEqual(chrome.progress, 1, "clamped")
        scroll(chrome, to: [55])
        XCTAssertEqual(chrome.progress, 1, "scrolling up gives no row back")
        scroll(chrome, to: [20])
        XCTAssertEqual(chrome.progress, 1, "not even most of the way up")
        scroll(chrome, to: [3])
        XCTAssertEqual(chrome.progress, 0, "only the very top expands it")
        XCTAssertFalse(chrome.isCollapsed)
    }

    @MainActor
    func testAHalfFoldFinishesFoldingAndReverseScrollNeverReExpands() {
        let down = ChromeScroll()
        down.anchor(at: 10)
        scroll(down, to: [40])
        down.settle()
        XCTAssertEqual(down.progress, 1)
        XCTAssertTrue(down.isCollapsed)
        let reverse = ChromeScroll()
        reverse.anchor(at: 10)
        scroll(reverse, to: [40, 30, 20, 12, 10])
        reverse.settle()
        XCTAssertEqual(reverse.progress, 1, "a half fold that turns back still ends folded")
    }

    @MainActor
    func testExpandingByHandWinsOverScrollingDownUntilTheTopOrANewScreen() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [60, 110, 160])
        XCTAssertTrue(chrome.isCollapsed)
        chrome.expandByHand()
        XCTAssertFalse(chrome.isCollapsed)
        XCTAssertTrue(chrome.isPinnedExpanded)
        scroll(chrome, to: [200, 260, 330])
        chrome.settle()
        XCTAssertEqual(chrome.progress, 0, "the rest of that scroll (momentum included) does not fold it")
        scroll(chrome, to: [300, 400, 520])
        XCTAssertEqual(chrome.progress, 0, "nor a later scroll down, or one up")
        XCTAssertFalse(chrome.isCollapsed)
        scroll(chrome, to: [3])
        XCTAssertFalse(chrome.isPinnedExpanded, "the top clears the pin")
        scroll(chrome, to: [60, 110])
        XCTAssertTrue(chrome.isCollapsed, "a scroll down from the top folds again")
    }

    @MainActor
    func testANewScreenOrPageClearsThePin() {
        for clear in [{ (c: ChromeScroll) in c.reset() }, { $0.expand() }] {
            let chrome = ChromeScroll()
            chrome.anchor(at: 10)
            chrome.expandByHand()
            clear(chrome)
            XCTAssertFalse(chrome.isPinnedExpanded)
            scroll(chrome, to: [60, 110, 160])
            XCTAssertTrue(chrome.isCollapsed)
        }
    }

    @MainActor
    func testAHeldDestinationNeverFoldsAndLeavingItStartsExpanded() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [100])
        XCTAssertTrue(chrome.isCollapsed, "a Library scrolled down")
        chrome.holdsExpanded = true
        XCTAssertFalse(chrome.isCollapsed, "coming to Listen from a folded Library: expanded")
        chrome.anchor(at: 10)
        scroll(chrome, to: [60, 120, 200, 300])
        XCTAssertEqual(chrome.progress, 0)
        XCTAssertFalse(chrome.isCollapsed)
        chrome.holdsExpanded = false
        chrome.reset()
        scroll(chrome, to: [100])
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
        XCTAssertEqual(chrome.progress, 1.0 / 90, accuracy: 0.001, "a 700 pt jump is not a finger")
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
