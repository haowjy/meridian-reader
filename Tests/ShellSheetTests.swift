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

    /// Voice settings' *Open full panel*: the panel over Voice settings, which stay when it closes.
    func testTheDebugPanelShowsOverASheetAndClosesBackToIt() {
        let shell = ShellState()
        shell.present(.voiceSettings)
        shell.present(.listenDebug)
        XCTAssertEqual(shell.sheet, .voiceSettings)
        XCTAssertEqual(shell.overSheet, .listenDebug)

        shell.overSheet = nil
        XCTAssertEqual(shell.sheet, .voiceSettings, "Voice settings stay")
    }

    func testTheSheetUnderneathTakesTheOneOverItAlong() {
        let shell = ShellState()
        shell.present(.voiceSettings)
        shell.present(.listenDebug)
        shell.sheet = nil
        XCTAssertNil(shell.overSheet)
    }

    func testOtherSheetsReplaceTheOneUp() {
        let shell = ShellState()
        shell.present(.voiceSettings)
        shell.present(.downloads)
        XCTAssertEqual(shell.sheet, .downloads)
        XCTAssertNil(shell.overSheet)
    }
}
