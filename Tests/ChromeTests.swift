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
        for (width, both, single, none) in [(375.0, 247.0, 295.0, 351.0), (393, 265, 313, 369), (430, 302, 350, 406)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, back: true, forward: true).field.rect.width, both)
            XCTAssertEqual(layout(.browse, width: w, back: true).field.rect.width, single)
            XCTAssertEqual(layout(.browse, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).field.rect.width, none)
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, none - 56, "row 2, nothing played: [pill][⋯]")
            XCTAssertEqual(layout(.library, width: w, played: true).pill.rect.width, none - 112, "[pill][▶][⋯]")
        }
    }

    func testCollapsedWidthsAtEveryPhone() {
        // (width, Browse with both arrows and nothing played, Browse with ▶, Browse new page with ▶, Library, Library with ▶)
        for (width, browseBoth, browsePlayed, browseNew, library, libraryPlayed) in
            [(375.0, 135.0, 127.0, 183.0, 239.0, 183.0), (393, 153, 145, 201, 257, 201), (430, 190, 182, 238, 294, 238)] {
            let w = CGFloat(width)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, back: true, forward: true).field.rect.width, browseBoth)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, played: true, back: true, forward: true).field.rect.width, browsePlayed)
            XCTAssertEqual(layout(.browse, width: w, progress: 1, played: true).field.rect.width, browseNew)
            XCTAssertEqual(layout(.library, width: w, progress: 1).field.rect.width, library)
            XCTAssertEqual(layout(.library, width: w, progress: 1, played: true).field.rect.width, libraryPlayed)
            XCTAssertEqual(layout(.reader, width: w, progress: 1, played: true).field.rect.width, libraryPlayed, "the title chip")
            XCTAssertEqual(layout(.library, width: w, played: true, keyboard: true).field.rect.width, libraryPlayed, "keyboard: [field][icon][▶][✕]")
            XCTAssertEqual(layout(.browse, width: w, played: true, back: true, forward: true, keyboard: true).field.rect.width, browseNew)
        }
    }

    func testPlayKeepsItsSlotAndTheIconSitsLeftOfIt() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                let expanded = layout(destination, width: width, played: true), collapsed = layout(destination, width: width, progress: 1, played: true)
                XCTAssertEqual(expanded.play.rect, collapsed.play.rect, "▶ does not travel")
                XCTAssertEqual(expanded.more.rect, collapsed.more.rect)
                XCTAssertEqual(collapsed.pill.rect.maxX + M.gap, collapsed.play.rect.minX, "[icon][▶]")
                XCTAssertEqual(collapsed.play.rect.maxX + M.gap, collapsed.more.rect.minX, "[▶][⋯]")
                XCTAssertEqual(expanded.more.rect.maxX, width - M.margin)
            }
        }
        XCTAssertEqual(layout(.reader).play.opacity, 0, "no ▶ before anything has played")
    }

    func testEveryPieceIsAsTallAsTheBarWideEnoughToTapAndInsideTheMargins() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases {
                for played in [false, true] {
                    for (progress, keyboard) in [(0.0, false), (1.0, false), (0.0, true)] where !(keyboard && destination == .reader) {
                        let l = layout(destination, width: width, progress: CGFloat(progress), played: played, back: true, forward: true, keyboard: keyboard)
                        let tag = "\(width) \(destination) played \(played) progress \(progress) keyboard \(keyboard)"
                        let shown = [l.pill, l.field, l.nav, l.play, l.more].filter { $0.opacity > 0.5 }
                        for piece in shown {
                            let isCard = destination == .reader && piece == l.field && progress == 0
                            XCTAssertEqual(piece.rect.height, isCard ? M.card : M.barHeight, tag)
                            XCTAssertGreaterThanOrEqual(piece.rect.width, M.minTapTarget, tag)
                            XCTAssertGreaterThanOrEqual(piece.rect.minX, M.margin - 0.01, tag)
                            XCTAssertLessThanOrEqual(piece.rect.maxX, width - M.margin + 0.01, tag)
                            XCTAssertEqual(piece.radius, M.barHeight / 2, "capsule \(tag)")
                        }
                        for (i, a) in shown.enumerated() {
                            for b in shown[(i + 1)...] where abs(a.rect.minY - b.rect.minY) < M.barHeight / 2 {
                                let gap = max(a.rect.minX, b.rect.minX) - min(a.rect.maxX, b.rect.maxX)
                                XCTAssertGreaterThanOrEqual(gap, M.gap - 0.01, tag)
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
        XCTAssertEqual(layout(.browse).nav.opacity, 0, "a new page has neither arrow")
        XCTAssertEqual(layout(.library, back: true).nav.opacity, 0, "only the Browser has arrows")
        XCTAssertEqual(layout(.browse, width: 320, progress: 1, played: true, back: true, forward: true).nav.rect.width, 0,
                       "folded on a narrow phone with ▶: the field keeps its minimum")
        XCTAssertGreaterThanOrEqual(layout(.browse, width: 320, progress: 1, played: true, back: true, forward: true).field.rect.width, M.minimumField)
    }

    func testEditBarReplacesRowTwoAndFullScreenShowsNothing() {
        let edit = ChromeLayout(width: 393, state: ChromeState(destination: .library, played: true, editing: true))
        XCTAssertEqual(edit.editBar.opacity, 1)
        XCTAssertEqual([edit.pill, edit.play, edit.more].map(\.opacity), [0, 0, 0])
        let full = ChromeLayout(width: 393, state: ChromeState(destination: .reader, fullScreen: true, played: true))
        XCTAssertEqual([full.pill, full.field, full.nav, full.play, full.more, full.editBar].map(\.opacity), Array(repeating: 0, count: 6))
        XCTAssertNil(full.top)
    }

    // MARK: Scroll

    @MainActor
    private func scroll(_ chrome: ChromeScroll, to offsets: [CGFloat]) { offsets.forEach { chrome.scrolled(to: $0) } }

    @MainActor
    func testProgressFollowsTheFingerBothWaysAtNinetyPointsATravel() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [55])
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001)
        scroll(chrome, to: [100])
        XCTAssertEqual(chrome.progress, 1, "clamped")
        scroll(chrome, to: [55])
        XCTAssertEqual(chrome.progress, 0.5, accuracy: 0.001, "scrolling up unfolds it again")
        scroll(chrome, to: [3])
        XCTAssertEqual(chrome.progress, 0, "the top is always expanded")
        XCTAssertFalse(chrome.isCollapsed)
    }

    @MainActor
    func testItSnapsToTheEndTheLastScrollWasHeadingFor() {
        let down = ChromeScroll()
        down.anchor(at: 10)
        scroll(down, to: [40])
        down.settle()
        XCTAssertEqual(down.progress, 1)
        XCTAssertTrue(down.isCollapsed)
        let up = ChromeScroll()
        up.anchor(at: 10)
        scroll(up, to: [200, 170, 150, 130, 120])
        up.settle()
        XCTAssertEqual(up.progress, 0, "last move was up: expanded")
    }

    @MainActor
    func testTheReaderUsesTheSameControllerAndScrollingUpExpandsIt() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 10)
        scroll(chrome, to: [120, 260])
        XCTAssertEqual(chrome.progress, 1)
        scroll(chrome, to: [240, 200])
        chrome.settle()
        XCTAssertEqual(chrome.progress, 0)
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
