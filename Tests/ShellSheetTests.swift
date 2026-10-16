import XCTest
@testable import MeridianReader

/// The shell's one sheet, and the listen debug panel, the one sheet that shows over another.
@MainActor
final class ShellSheetTests: XCTestCase {
    func testTheDebugPanelIsTheSheetWhenNoneIsUp() {
        let shell = ShellState()
        shell.present(.listenDebug)
        XCTAssertEqual(shell.sheet, .listenDebug)
        XCTAssertNil(shell.overSheet)
    }

    /// Settings › Developer › Listen Debug Panel: the panel over Settings, which stay when it closes.
    func testTheDebugPanelShowsOverASheetAndClosesBackToIt() {
        let shell = ShellState()
        shell.present(.settings)
        shell.present(.listenDebug)
        XCTAssertEqual(shell.sheet, .settings)
        XCTAssertEqual(shell.overSheet, .listenDebug)

        shell.overSheet = nil
        XCTAssertEqual(shell.sheet, .settings, "Settings stay")
    }

    func testTheSheetUnderneathTakesTheOneOverItAlong() {
        let shell = ShellState()
        shell.present(.settings)
        shell.present(.listenDebug)
        shell.sheet = nil
        XCTAssertNil(shell.overSheet)
    }

    func testOtherSheetsReplaceTheOneUp() {
        let shell = ShellState()
        shell.present(.settings)
        shell.present(.downloads)
        XCTAssertEqual(shell.sheet, .downloads)
        XCTAssertNil(shell.overSheet)
    }
}
