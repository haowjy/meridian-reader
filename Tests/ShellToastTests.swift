import XCTest
@testable import MeridianReader

/// The shell's toast goes by itself once a place showing it has waited its time; a place that
/// goes away meanwhile (a sheet closing just as the toast comes up) doesn't take it with it.
@MainActor
final class ShellToastTests: XCTestCase {
    func testAToastGoesOnceItsTimeIsUp() async throws {
        let shell = ShellState()
        shell.showToast(ShellToast(message: "Couldn’t save"))
        let id = try XCTUnwrap(shell.toast?.id)
        await shell.expireToast(id, after: .milliseconds(10))
        XCTAssertNil(shell.toast)
    }

    func testAPlaceThatGoesAwayLeavesTheToastShowing() async throws {
        let shell = ShellState()
        shell.showToast(ShellToast(message: "Couldn’t save"))
        let id = try XCTUnwrap(shell.toast?.id)
        let wait = Task { await shell.expireToast(id, after: .seconds(30)) }
        wait.cancel()
        await wait.value
        XCTAssertEqual(shell.toast?.id, id, "still showing, for the places that stay")
    }

    func testANewerToastStaysWhenTheOlderOnesTimeIsUp() async throws {
        let shell = ShellState()
        shell.showToast(ShellToast(message: "Couldn’t move"))
        let older = try XCTUnwrap(shell.toast?.id)
        shell.showToast(ShellToast(message: "Couldn’t save"))
        await shell.expireToast(older, after: .milliseconds(10))
        XCTAssertEqual(shell.toast?.message, "Couldn’t save")
    }
}
