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

    func testEditHoldsTheChromeExpandedAndTheKeyboardHidesTheCapsule() {
        var state = ChromeState(destination: .browse, progress: 1)
        XCTAssertEqual(state.collapse, 1)
        XCTAssertEqual(state.capsule, 1)
        state.readerMode = true
        XCTAssertEqual(state.collapse, 1, "reader mode in Scroll mode folds like a page (the host holds Pages mode expanded)")
        state = ChromeState(destination: .library, progress: 1, editing: true)
        XCTAssertEqual(state.collapse, 0)
        let typing = ChromeState(destination: .library, progress: 1, keyboard: true)
        XCTAssertEqual(typing.fold, 1, "the keyboard's row")
        XCTAssertEqual(typing.capsule, 0, "no capsule while typing: the field's row is the only row")
    }

    func testListenHoldsTheChromeExpandedWhateverTheScroll() {
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).collapse, 0)
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).fold, 0)
        XCTAssertEqual(ChromeState(destination: .library, progress: 1).collapse, 1)
        XCTAssertEqual(ChromeState(destination: .reader, progress: 1).capsule, 0)
    }

    func testEditKeepsBothRowsAndListenNeverShowsTheCapsuleWhateverTheScroll() {
        func state(_ destination: ChromeDestination, editing: Bool = false) -> ChromeState {
            ChromeState(destination: destination, progress: 1, played: true, editing: editing)
        }
        let scrolled = ChromeLayout(width: 393, state: state(.browse))
        let edit = ChromeLayout(width: 393, state: state(.library, editing: true))
        let listen = ChromeLayout(width: 393, state: state(.reader))
        XCTAssertTrue(scrolled.capsule.isShown)
        XCTAssertFalse(scrolled.pill.isShown, "scrolled: the rows are the capsule")
        XCTAssertFalse(edit.capsule.isShown, "Edit: row 2 stays")
        XCTAssertTrue(edit.editBar.isShown)
        XCTAssertFalse(listen.capsule.isShown, "Listen never folds")
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
        XCTAssertFalse(library.listen.isShown, "the Library's capsule is the field itself")
    }

    // MARK: Tokens

    func testOneBarHeightDerivesEveryFootprintAndWidth() {
        XCTAssertEqual(M.barHeight, 48)
        XCTAssertEqual(M.footprint, 116)
        XCTAssertEqual(M.collapsedFootprint, 60, "the keyboard's row")
        XCTAssertEqual(M.capsuleFootprint, 40, "the capsule: 4 + 28 + 8")
        XCTAssertEqual(M.navSingleWidth, 48)
        XCTAssertEqual(M.navPairWidth, 96)
        XCTAssertEqual([M.capsuleHeight, M.capsuleFontSize, M.capsuleSidePadding, M.capsuleMaxWidth], [28, 12, 10, 240])
        XCTAssertEqual(M.capsuleHitOutset, 8, "28 + 2 * 8 = the 44 pt hit area")
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
            XCTAssertEqual(layout(.library, width: w).pill.rect.width, 235, "row 2, nothing played: ▶'s slot stays reserved and empty, and the pill is the SE's 235 on every phone")
            XCTAssertEqual(layout(.library, width: w, played: true).pill.rect.width, 235, "[pill][▶][⋯]")
        }
    }

    /// Typing: the field and Cancel only (no screen icon, ▶, ⋯ or arrows), margin to margin on every phone:
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
                    XCTAssertEqual(l.field.rect.minY, rest.more.rect.minY, tag)
                    XCTAssertEqual(l.more.rect.minY, rest.more.rect.minY, tag)
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
        for (width, x) in [(375.0, 257.0), (393, 266), (430, 284.5)] {  // the centred 351 pt row: ▶ at width − (width − 351) / 2 − 106
            XCTAssertEqual(layout(.library, width: CGFloat(width), played: true).play.rect.minX, x, "▶ at \(width)")
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
        XCTAssertEqual(layout(.library, width: 402, played: true).expandedPillWidth, 235)
    }

    func testPlayKeepsItsSlotAndTheMoreEndsTheCentredRow() {
        for width in [375.0, 393, 430].map({ CGFloat($0) }) {
            for destination in ChromeDestination.allCases where destination != .reader {
                let expanded = layout(destination, width: width, played: true)
                XCTAssertEqual(expanded.pill.rect.maxX + M.rowGap, expanded.play.rect.minX, "[pill][▶]")
                XCTAssertEqual(expanded.play.rect.maxX + M.rowGap, expanded.more.rect.minX, "[▶][⋯]")
                XCTAssertEqual(expanded.more.rect.maxX, width - max(M.margin, (width - M.bottomRowWidth) / 2), "⋯ ends the centred row")
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
                XCTAssertFalse(l.capsule.isShown, "Listen never folds")
                XCTAssertEqual(l.pill.rect, library.pill.rect, "the pill is the Library's, not wider, at \(width)")
                XCTAssertEqual(l.more.rect, library.more.rect)
                XCTAssertEqual(l.pill.rect.maxX + M.rowGap, library.play.rect.minX, "▶'s slot stays empty between the pill and ⋯")
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

    /// The bottom row is a fixed 351 pt block, the SE's: the same size on every phone, centred with equal space
    /// either side on a wider one, never stretched, and its pill identical across 375 / 393 / 402 / 430.
    func testTheBottomRowIsOneFixedSizeCentredOnWiderPhones() {
        XCTAssertEqual(M.pillWidth, 235)
        XCTAssertEqual(M.bottomRowWidth, 351)
        XCTAssertEqual(M.margin, 12, "the SE's 375 − 351 = 24: margin 12 each side")
        let widths: [CGFloat] = [375, 393, 402, 430]
        for played in [false, true] {
            for destination in ChromeDestination.allCases {
                let se = layout(destination, width: 375, played: played)
                for width in widths {
                    let l = layout(destination, width: width, played: played)
                    let inset = (width - 351) / 2
                    XCTAssertEqual(l.pill.rect.width, se.pill.rect.width, "same pill width at \(width)")
                    XCTAssertEqual(l.pill.rect.minX, inset, "the row starts at an equal inset at \(width)")
                    XCTAssertEqual(width - l.more.rect.maxX, inset, "and ends at the same inset at \(width)")
                    XCTAssertEqual(l.more.rect.width, M.barHeight)
                    XCTAssertEqual(l.more.rect.minX - l.pill.rect.maxX, 2 * M.rowGap + M.barHeight, "[pill][▶ slot][⋯] at \(width)")
                    XCTAssertEqual(l.pill.rect.minY, se.pill.rect.minY)
                    XCTAssertEqual(l.more.rect.minY, se.more.rect.minY)
                }
            }
        }
        // The pill's x is the one centring offset from the SE: a phone's pill is the SE's, moved right.
        for width in widths {
            let l = layout(.library, width: width)
            XCTAssertEqual(l.pill.rect.minX - layout(.library, width: 375).pill.rect.minX, (width - 375) / 2)
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

    func testFoldingShrinksTheRowsIntoTheCapsuleEveryFrame() {
        let expanded = layout(.browse, progress: 0, played: true, back: true)
        let half = layout(.browse, progress: 0.5, played: true, back: true)
        let folded = layout(.browse, progress: 1, played: true, back: true)
        XCTAssertFalse(expanded.capsule.isShown)
        XCTAssertTrue(half.capsule.isShown && half.pill.isShown, "halfway both are on screen, so the glass blends one into the other")
        XCTAssertLessThan(half.pill.rect.width, expanded.pill.rect.width)
        XCTAssertLessThan(half.capsule.rect.height, M.capsuleHeight)
        let f = half.pill.rect.width / expanded.pill.rect.width
        XCTAssertEqual(half.pill.rect.midX, 393 / 2 + (expanded.pill.rect.midX - 393 / 2) * f, accuracy: 0.01,
                       "the pill shrinks about the capsule's centre")
        XCTAssertEqual(folded.capsule.rect.height, M.capsuleHeight)
        XCTAssertEqual([folded.pill, folded.field, folded.nav, folded.play, folded.more, folded.listen].map(\.isShown),
                       Array(repeating: false, count: 6), "folded: nothing but the capsule")
        var last: CGFloat = -1
        for step in 0...20 {
            let h = layout(.browse, progress: CGFloat(step) / 20, played: true).capsule.rect.height
            XCTAssertGreaterThanOrEqual(h, last, "the capsule only grows as the rows fold")
            last = h
        }
    }

    /// The capsule at the two phones that matter (the 17 Pro's 402, the SE's 375): 28 tall, as wide as its name (to 240),
    /// centred, 8 above the safe line, a 44 pt hit area, and nothing else on screen.
    func testTheCapsuleIs28TallCentredWithA44HitAreaAndTheRowsAreGone() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            for destination in [ChromeDestination.browse, .library] {
                for (text, expected) in [(0.0, 28.0), (60.0, 80), (110, 130), (300, 240)] {
                    let capsuleWidth = M.capsuleWidth(forTextWidth: CGFloat(text))
                    XCTAssertEqual(capsuleWidth, CGFloat(expected), "\(text) pt of title")
                    let l = ChromeLayout(width: width, state: ChromeState(destination: destination, progress: 1, played: true,
                                                                          canGoBack: true, canGoForward: true, capsuleWidth: capsuleWidth))
                    let tag = "\(width) \(destination) \(text)"
                    XCTAssertTrue(l.capsule.isShown, tag)
                    XCTAssertEqual(l.capsule.rect.height, 28, tag)
                    XCTAssertEqual(l.capsule.rect.width, capsuleWidth, tag)
                    XCTAssertLessThanOrEqual(l.capsule.rect.width, 240, tag)
                    XCTAssertEqual(l.capsule.rect.midX, width / 2, tag)
                    XCTAssertEqual(l.capsule.rect.maxY, M.readerFootprint - M.bottomPadding, "8 above the safe line: \(tag)")
                    let hit = l.capsule.rect.insetBy(dx: -M.capsuleHitOutset, dy: -M.capsuleHitOutset)
                    XCTAssertEqual(hit.height, 44, tag)
                    XCTAssertEqual(hit.width, capsuleWidth + 16, tag)
                    XCTAssertEqual(l.top, l.capsule.rect.minY, "nothing else is on screen: \(tag)")
                    XCTAssertEqual(l.capsule.radius, 14, tag)
                }
            }
        }
    }

    func testTheCapsuleIsOnlyThereFoldedAndNeverTypingOrOnListenOrEditing() {
        for width in [375.0, 402].map({ CGFloat($0) }) {
            XCTAssertFalse(layout(.browse, width: width, progress: 0).capsule.isShown, "expanded")
            XCTAssertFalse(layout(.library, width: width, progress: 1, keyboard: true).capsule.isShown, "typing")
            XCTAssertFalse(layout(.reader, width: width, progress: 1).capsule.isShown, "Listen")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .library, progress: 1, editing: true)).capsule.isShown, "Edit")
            XCTAssertFalse(ChromeLayout(width: width, state: ChromeState(destination: .browse, progress: 1, fullScreen: true)).capsule.isShown, "full screen")
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
