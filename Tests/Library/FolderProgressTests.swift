import XCTest
@testable import MeridianReader

/// What a folder's row and its header show comes from one `FolderProgress`, so they agree on
/// whether it has started: marking pages finished starts it even before anything in it played.
@MainActor
final class FolderProgressTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func folder(with count: Int) throws -> (Folder, [Page]) {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        let pages = try (1...count).map { try library.save(env.article("https://example.com/\($0)", title: "Page \($0)")) }
        try library.move(pages.map(LibraryItem.page), to: folder)
        return (folder, library.playOrder(of: folder))
    }

    func testANeverPlayedFolderHasNotStarted() throws {
        let (folder, pages) = try folder(with: 3)
        let progress = FolderProgress(folder: folder, pages: pages, playingKey: nil, library: library)
        XCTAssertFalse(progress.hasStarted)
        XCTAssertNil(progress.fraction)
        XCTAssertEqual(progress.buttonTitle.title, "Play")
    }

    func testFinishingPagesStartsItForTheRowAndTheHeaderAlike() throws {
        let (folder, pages) = try folder(with: 3)
        try library.setFinished(Array(pages.prefix(2)), true)
        XCTAssertNil(folder.currentPageKey, "nothing in it has played")
        let progress = FolderProgress(folder: folder, pages: pages, playingKey: nil, library: library)
        XCTAssertTrue(progress.hasStarted, "the row names its place")
        XCTAssertNotNil(progress.fraction, "the header shows how far")
        XCTAssertEqual(progress.buttonTitle.title, "Continue", "and its button continues")
    }

    func testThePagePlayingNamesTheButton() throws {
        let (folder, pages) = try folder(with: 2)
        let progress = FolderProgress(folder: folder, pages: pages, playingKey: pages[1].listenKey, library: library)
        XCTAssertEqual(progress.buttonTitle.title, "Playing")
        XCTAssertEqual(progress.buttonTitle.detail, "2 of 2")
    }
}
