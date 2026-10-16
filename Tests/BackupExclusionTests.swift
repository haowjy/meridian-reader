import XCTest
@testable import MeridianReader

/// Audio and downloads the app can make again stay out of backups: the launch flags the audio
/// cache (`AppComposition.prepareAudioCache`), the engines' download folders and the timing log
/// (`runLaunchMaintenance`); a directory's flag covers what it holds, including what was already
/// there.
@MainActor
final class BackupExclusionTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "BackupExclusion-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAMissingDirectoryIsCreatedAndFlagged() {
        let cache = dir.appending(path: "TTSCache", directoryHint: .isDirectory)
        XCTAssertTrue(BackupExclusion.exclude(cache))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(BackupExclusion.isExcluded(cache))
        XCTAssertTrue(BackupExclusion.exclude(cache), "again: already flagged")
    }

    /// An existing cache (an earlier version wrote it unflagged) is flagged as it is: nothing in
    /// it moves or goes.
    func testAnExistingDirectoryKeepsItsFilesAndIsFlagged() throws {
        let article = dir.appending(path: "TTSCache/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: article, withIntermediateDirectories: true)
        let unit = article.appending(path: "p0000.caf")
        try Data([1, 2, 3]).write(to: unit)
        let root = dir.appending(path: "TTSCache", directoryHint: .isDirectory)
        XCTAssertFalse(BackupExclusion.isExcluded(root))

        XCTAssertTrue(BackupExclusion.exclude(root))
        XCTAssertTrue(BackupExclusion.isExcluded(root))
        XCTAssertEqual(try Data(contentsOf: unit), Data([1, 2, 3]))
    }

    func testTheLaunchFlagsTheAudioCache() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        XCTAssertFalse(BackupExclusion.isExcluded(env.cache.root))
        AppComposition.prepareAudioCache(library: env.library, tts: env.tts, migrations: [])
        XCTAssertTrue(BackupExclusion.isExcluded(env.cache.root))
    }

    /// Kokoro's downloads: FluidAudio's model cache and the ONNX model's folder.
    func testKokoroNamesItsDownloadFolders() {
        let names = FluidAudioProvider().regenerableDirectories.map(\.lastPathComponent)
        XCTAssertEqual(names, ["fluidaudio", "CPURoute"])
        XCTAssertTrue(KokoroONNXModelStore.directory.path.hasPrefix(FluidAudioProvider().regenerableDirectories[1].path))
    }
}
