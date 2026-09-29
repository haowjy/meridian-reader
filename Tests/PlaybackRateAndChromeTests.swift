import AVFoundation
import XCTest
@testable import Reader

/// Nav I: speed changes apply in place (player time-stretch, no restart / re-queue), developer
/// options default per build, the five-slot bottom toolbar grid.
@MainActor
final class PlaybackRateAndChromeTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func tearDown() {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    /// A mono sine CAF `seconds` long.
    private func makeTone(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rate-\(UUID().uuidString).caf")
        tempFiles.append(url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 24_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = 0.05 * sinf(Float(i) * 2 * .pi * 220 / 24_000) }
        try file.write(from: buffer)
        return url
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testSpeedChangeAppliesInPlaceWithoutRestartingTheUnit() throws {
        let queue = ChunkPlaybackQueue()
        defer { queue.clear() }
        var started: [Int] = []
        queue.onUnitStarted = { started.append($0.paragraphIndex) }
        queue.enqueue(.init(paragraphIndex: 0, fileURL: try makeTone(seconds: 3)))
        queue.enqueue(.init(paragraphIndex: 1, fileURL: try makeTone(seconds: 0.6)))
        spin(0.5)
        guard let before = queue.currentPosition else { return XCTFail("nothing playing") }
        XCTAssertEqual(before.item.paragraphIndex, 0)
        XCTAssertEqual(queue.currentPlayerRate, 1)

        queue.setRate(1.5)

        let after = try XCTUnwrap(queue.currentPosition)
        XCTAssertEqual(after.item.paragraphIndex, 0, "same unit keeps playing")
        XCTAssertGreaterThanOrEqual(after.time, before.time, "not restarted from the beginning")
        XCTAssertEqual(queue.currentPlayerRate, 1.5)
        XCTAssertEqual(started, [0], "no re-queue / restart")
        XCTAssertEqual(queue.playbackRate, 1.5)

        // The next unit starts at the new speed; clear() keeps it (a setting, not queue state).
        queue.clear()
        XCTAssertEqual(queue.playbackRate, 1.5)
        queue.enqueue(.init(paragraphIndex: 2, fileURL: try makeTone(seconds: 1)))
        XCTAssertEqual(queue.currentPlayerRate, 1.5)
    }

    func testRateMultiplierPersistsAndReachesThePlayerAndLockScreen() {
        let suite = "RateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateTests-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: root.appendingPathComponent("guard")))
        let nowPlaying = NowPlayingController(commandCenter: nil, infoCenter: nil)
        let saved = UserDefaults.standard.object(forKey: "reader.rateMultiplier")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "reader.rateMultiplier") }
            else { UserDefaults.standard.removeObject(forKey: "reader.rateMultiplier") }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let speech = SpeechController(engines: registry, localTTS: coordinator,
                                      audioSession: ListenAudioSession(managesSystemSession: false), nowPlaying: nowPlaying)
        defer { speech.stop() }
        speech.setRateMultiplier(1.25)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "reader.rateMultiplier"), 1.25, "persisted")
        XCTAssertEqual(coordinator.localEngineInstance.playbackRate, 1.25, "player time-stretch rate")

        let session = SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["One two three.", "Four five."]),
                                    title: "Rate")
        speech.start(session, fromParagraph: 0)
        speech.pause()
        speech.setRateMultiplier(1.75)
        XCTAssertEqual(nowPlaying.lastInfo?.rate, 1.75, "lock screen reports the new rate")
        XCTAssertEqual(coordinator.localEngineInstance.playbackRate, 1.75)
        // Local playback never restarts on a speed change; only Apple's synthesizer must re-speak.
        XCTAssertFalse(SpeechController.rateChangeRestartsUtterance(usesLocalPlayback: true))
        XCTAssertTrue(SpeechController.rateChangeRestartsUtterance(usesLocalPlayback: false))
    }

    func testDeveloperOptionsDefaultPerBuild() {
        XCTAssertFalse(DeveloperOptions.resolve(stored: nil, isDebugBuild: false), "hidden in Release")
        XCTAssertTrue(DeveloperOptions.resolve(stored: nil, isDebugBuild: true), "on in Debug builds")
        XCTAssertTrue(DeveloperOptions.resolve(stored: true, isDebugBuild: false), "unlocked in Release")
        XCTAssertFalse(DeveloperOptions.resolve(stored: false, isDebugBuild: true))
    }

    func testFiveSlotToolbarGrid() {
        let width: CGFloat = 369
        let slot = BottomToolbarLayout.slotWidth(rowWidth: width)
        XCTAssertEqual(slot, width / 5, accuracy: 1e-9)
        let centers = (0..<5).map { BottomToolbarLayout.slotCenterX($0, rowWidth: width) }
        for i in 1..<5 { XCTAssertEqual(centers[i] - centers[i - 1], slot, accuracy: 1e-9, "evenly spaced") }
        // Browse [‹][›][Search][ ][⋯]: 4 views → slots 0, 1, 2, 4. Reader: 5 views → 0…4.
        XCTAssertEqual((0..<4).map { BottomToolbarLayout.slot(forSubview: $0, count: 4) }, [0, 1, 2, 4])
        XCTAssertEqual((0..<5).map { BottomToolbarLayout.slot(forSubview: $0, count: 5) }, [0, 1, 2, 3, 4])
        // Mini player play/pause centered on slot 5 (the ⋯ column).
        let pad = MiniPlayerBar.trailingPadding(rowWidth: width)
        XCTAssertEqual(width - pad - MiniPlayerBar.playSize / 2, centers[4], accuracy: 1e-9)
    }
}
