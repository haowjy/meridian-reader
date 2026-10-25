import XCTest
@testable import MeridianReader

/// The compact chrome's rules: what shows (`ChromeState`), where (`ChromeGeometry`) and when it
/// collapses (`ChromeScroll`). Pure values, no screen.
final class ChromeTests: XCTestCase {
    private typealias M = ChromeMetrics
    private let width: CGFloat = 393

    private func geometry(_ state: ChromeState) -> ChromeGeometry { ChromeGeometry(width: width, state: state) }

    // MARK: State

    func testPresenceIsTwoIndependentFlags() {
        var state = ChromeState(destination: .reader, presence: ChromePresence(collapsed: true))
        XCTAssertEqual(state.rows, .one)
        state.presence.fullScreen = true
        XCTAssertEqual(state.rows, .none)
        state.presence.fullScreen = false
        XCTAssertEqual(state.rows, .one, "leaving full screen returns to the previous collapsed")
    }

    func testFullScreenIsTheReadersAlone() {
        let state = ChromeState(destination: .library, presence: ChromePresence(fullScreen: true))
        XCTAssertEqual(state.rows, .two)
    }

    func testReaderModeEditingAndKeyboardDecideTheRows() {
        let collapsed = ChromePresence(collapsed: true)
        XCTAssertEqual(ChromeState(destination: .browse, presence: collapsed, readerMode: true).rows, .two)
        XCTAssertEqual(ChromeState(destination: .library, presence: collapsed, editing: true).rows, .two)
        XCTAssertEqual(ChromeState(destination: .library, keyboard: true).rows, .one)
    }

    // MARK: Geometry

    func testExpandedRowsOnEveryDestination() {
        let browse = geometry(ChromeState(destination: .browse, played: true, canGoBack: true, canGoForward: true))
        XCTAssertEqual(browse.rows, .two)
        XCTAssertEqual(browse.pill?.height, M.row2Height)
        XCTAssertEqual(browse.field?.height, M.row1Height)
        XCTAssertEqual(browse.navigation?.width, M.navPairWidth)
        XCTAssertNotNil(browse.play)
        XCTAssertEqual(browse.more?.maxX, width - M.margin)
        XCTAssertEqual(browse.fade?.rise, M.fadeHeight)
    }

    func testReaderExpandedIsRowTwoAlone() {
        let reader = geometry(ChromeState(destination: .reader))
        XCTAssertNil(reader.field)
        XCTAssertNil(reader.play, "no ▶ before anything has played")
        XCTAssertEqual(reader.fade?.rise, 0, "the band stands above row 2: no rise")
        let played = geometry(ChromeState(destination: .reader, played: true))
        XCTAssertEqual(played.play?.width, M.row2Height)
        XCTAssertEqual(played.pill?.minX, M.margin)
        XCTAssertEqual(played.pill?.maxX, (played.play?.minX ?? 0) - M.gap)
    }

    func testCollapsedIsOneRowOfEqualPieces() {
        let state = ChromeState(destination: .reader, presence: ChromePresence(collapsed: true), played: true)
        let g = geometry(state)
        XCTAssertEqual(g.rows, .one)
        XCTAssertNil(g.pill)
        let heights = [g.field, g.play, g.icon, g.more].compactMap { $0?.height }
        XCTAssertEqual(heights, Array(repeating: M.collapsedHeight, count: 4), "title chip, ▶, icon, ⋯")
        XCTAssertEqual(g.fade?.rise, M.fadeHeight, "the collapsed Reader keeps the rise")
        XCTAssertEqual(g.top, M.footprint - M.bottomPadding - M.collapsedHeight)
    }

    func testFullScreenHasNoPiecesAndNoFade() {
        let g = geometry(ChromeState(destination: .reader, presence: ChromePresence(fullScreen: true), played: true))
        XCTAssertEqual(g.rows, .none)
        XCTAssertTrue([g.field, g.back, g.forward, g.pill, g.play, g.icon, g.more].allSatisfy { $0 == nil })
        XCTAssertNil(g.fade)
    }

    func testKeyboardIsOneRowWithoutPlayOrArrows() {
        let g = geometry(ChromeState(destination: .browse, played: true, canGoBack: true, canGoForward: true, keyboard: true))
        XCTAssertEqual(g.rows, .one)
        XCTAssertNil(g.play)
        XCTAssertNil(g.navigation)
        XCTAssertNotNil(g.icon)
    }

    // MARK: Scroll

    @MainActor
    private func scroll(_ chrome: ChromeScroll, to offsets: [CGFloat], upExpands: Bool = true) {
        offsets.forEach { chrome.scrolled(to: $0, upExpands: upExpands) }
    }

    @MainActor
    func testScrollingDownCollapsesAndTheTopExpands() {
        let chrome = ChromeScroll()
        scroll(chrome, to: [10, 20, 40])
        XCTAssertTrue(chrome.isScrolledDown)
        scroll(chrome, to: [0])
        XCTAssertFalse(chrome.isScrolledDown)
    }

    @MainActor
    func testScrollingUpExpandsLibraryAndBrowse() {
        let chrome = ChromeScroll()
        scroll(chrome, to: [10, 40, 80, 70, 60, 50])
        XCTAssertFalse(chrome.isScrolledDown)
    }

    @MainActor
    func testReaderStaysCollapsedOnScrollUpUnlessItsSwitchIsOn() {
        let up: [CGFloat] = [10, 40, 80, 70, 60, 50]
        let off = ChromeScroll()
        scroll(off, to: up, upExpands: false)
        XCTAssertTrue(off.isScrolledDown)
        scroll(off, to: [0], upExpands: false)
        XCTAssertFalse(off.isScrolledDown, "the top still expands")
        let on = ChromeScroll()
        scroll(on, to: up, upExpands: true)
        XCTAssertFalse(on.isScrolledDown)
    }

    @MainActor
    func testAProgrammaticMoveReanchorsWithoutDecidingTheCollapse() {
        let chrome = ChromeScroll()
        chrome.anchor(at: 295)
        XCTAssertFalse(chrome.isScrolledDown)
        chrome.scrolled(to: 290, upExpands: false)
        XCTAssertFalse(chrome.isScrolledDown, "a restored spot is not the start of a scroll up from 0")
        chrome.scrolled(to: 330, upExpands: false)
        XCTAssertTrue(chrome.isScrolledDown)
        chrome.anchor(at: 0)
        XCTAssertFalse(chrome.isScrolledDown, "a move to the top expands")
    }

    @MainActor
    func testScrollControllerOwnsBothPresenceFlags() {
        let chrome = ChromeScroll()
        scroll(chrome, to: [10, 40, 80])
        chrome.setFullScreen(true)
        XCTAssertEqual(chrome.presence, ChromePresence(collapsed: true, fullScreen: true))
        scroll(chrome, to: [120, 200], upExpands: false)
        XCTAssertTrue(chrome.fullScreen, "scrolling never leaves full screen")
        chrome.reset()
        XCTAssertEqual(chrome.presence, ChromePresence(), "a new screen starts expanded, out of full screen")
    }
}
