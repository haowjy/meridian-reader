import XCTest
@testable import MeridianReader

/// The app's files stay where an install already has them: a renamed path loses the library,
/// the audio or a setting file.
final class AppDirectoriesTests: XCTestCase {
    func testEveryFileStaysWhereAnInstallHasIt() {
        let support = URL.applicationSupportDirectory.standardizedFileURL.path
        func relative(_ url: URL) -> String {
            String(url.standardizedFileURL.path.dropFirst(support.count))
        }
        XCTAssertEqual(AppDirectories.applicationSupport.standardizedFileURL.path, support)
        XCTAssertEqual(relative(AppDirectories.localStore), "/default.store")
        XCTAssertEqual(relative(AppDirectories.libraryStore), "/library.store")
        XCTAssertEqual(relative(AppDirectories.audioCache), "/TTSCache")
        XCTAssertEqual(relative(AppDirectories.pendingBakeJobs), "/PendingBakeJobs.json")
        XCTAssertEqual(relative(AppDirectories.downloads), "/Downloads.json")
        XCTAssertEqual(relative(AppDirectories.imports), "/Imports")
        XCTAssertEqual(relative(AppDirectories.legacyBookmarks), "/Bookmarks/bookmarks.json")
        XCTAssertEqual(relative(AppDirectories.listenTiming), "/ListenTiming")
        XCTAssertEqual(relative(AppDirectories.listenResumePoint), "/ListenTiming/listen_resume.json")
    }
}
