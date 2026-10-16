import AVFoundation
import XCTest
@testable import MeridianReader

/// Speed changes apply in place (player time-stretch, no restart / re-queue), developer
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

    /// Runs the main run loop until `condition` holds (the player's callbacks arrive on it).
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func testSpeedChangeAppliesInPlaceWithoutRestartingTheUnit() throws {
        let queue = ChunkPlaybackQueue()
        defer { queue.clear() }
        var started: [Int] = []
        queue.onUnitStarted = { started.append($0.paragraphIndex) }
        queue.enqueue(.init(paragraphIndex: 0, fileURL: try makeTone(seconds: 3), source: .baked, duration: 3))
        queue.enqueue(.init(paragraphIndex: 1, fileURL: try makeTone(seconds: 0.6), source: .baked, duration: 0.6))
        // Well into the first unit, so a restart (back to 0) can't pass for where it was.
        XCTAssertTrue(waitUntil(2.5) { (queue.currentPosition?.time ?? 0) >= 0.3 }, "the first unit plays")
        guard let before = queue.currentPosition else { return XCTFail("nothing playing") }
        XCTAssertEqual(before.item.paragraphIndex, 0)
        XCTAssertEqual(queue.currentPlayerRate, 1)

        queue.setRate(1.5)

        // The player reports its time through the time-stretch's output latency, so the time read
        // just after a rate change can sit a few milliseconds behind the one read before it.
        let after = try XCTUnwrap(queue.currentPosition)
        XCTAssertEqual(after.item.paragraphIndex, 0, "same unit keeps playing")
        XCTAssertEqual(after.time, before.time, accuracy: 0.1, "carries on where it was, not restarted from the beginning")
        XCTAssertEqual(queue.currentPlayerRate, 1.5)
        XCTAssertEqual(started, [0], "no re-queue / restart")
        XCTAssertEqual(queue.playbackRate, 1.5)

        // The next unit starts at the new speed; clear() keeps it (a setting, not queue state).
        queue.clear()
        XCTAssertEqual(queue.playbackRate, 1.5)
        queue.enqueue(.init(paragraphIndex: 2, fileURL: try makeTone(seconds: 1), source: .baked, duration: 1))
        XCTAssertEqual(queue.currentPlayerRate, 1.5)
    }

    func testRateMultiplierPersistsAndReachesThePlayerAndLockScreen() {
        let stack = TestSpeech()
        let nowPlaying = stack.nowPlaying
        let saved = UserDefaults.standard.object(forKey: "reader.rateMultiplier")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "reader.rateMultiplier") }
            else { UserDefaults.standard.removeObject(forKey: "reader.rateMultiplier") }
            stack.tearDown()
        }
        let speech = stack.speech
        speech.setRateMultiplier(1.25)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "reader.rateMultiplier"), 1.25, "persisted")
        XCTAssertEqual(speech.localEngine.player.playbackRate, 1.25, "player time-stretch rate")

        let session = SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["One two three.", "Four five."]),
                                    title: "Rate")
        speech.start(session)
        speech.pause()
        speech.setRateMultiplier(1.75)
        XCTAssertEqual(nowPlaying.lastInfo?.rate, 1.75, "lock screen reports the new rate")
        XCTAssertEqual(speech.localEngine.player.playbackRate, 1.75)
    }

    /// A speed stored outside the list (an older build allowed up to 4×) loads as the nearest
    /// allowed one, and the player, the Apple voice and the lock screen all get that one.
    func testAStoredSpeedOutsideTheListLoadsAsTheNearestEverywhere() {
        let saved = UserDefaults.standard.object(forKey: "reader.rateMultiplier")
        UserDefaults.standard.set(3.0, forKey: "reader.rateMultiplier")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "reader.rateMultiplier") }
            else { UserDefaults.standard.removeObject(forKey: "reader.rateMultiplier") }
        }
        let fixture = TestSpeech()
        defer { fixture.tearDown() }
        let speech = fixture.speech
        XCTAssertEqual(speech.rateMultiplier, 2)

        speech.start(SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["One two three."]), title: "Rate"))
        XCTAssertEqual(speech.localEngine.player.playbackRate, 2, "the on-device player")
        XCTAssertEqual(fixture.apple.rate, 2, "the Apple voice")
        XCTAssertEqual(speech.lockScreen.lastInfo?.rate, 2, "the lock screen")
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
        // An item sits in the slot it names, whatever its position: Library [‹][ ][＋][ ][⋯]
        // keeps ⋯ in slot 5 and ＋ in slot 3; unnamed items take their position (the transport).
        XCTAssertEqual(BottomToolbarLayout.slot(named: 4, forSubview: 2), 4)
        XCTAssertEqual(BottomToolbarLayout.slot(named: 2, forSubview: 1), 2)
        XCTAssertEqual((0..<5).map { BottomToolbarLayout.slot(named: nil, forSubview: $0) }, [0, 1, 2, 3, 4])
        XCTAssertEqual(BottomToolbarLayout.slot(named: 9, forSubview: 0), 4, "within the row")
        // The Now Playing bar's play/pause centered on slot 5 (the ⋯ column) of a full-width bar.
        let pad = NowPlayingBar.trailingPadding(rowWidth: width)
        XCTAssertEqual(width - pad - BottomChrome.minTapTarget / 2, centers[4], accuracy: 1e-9)
    }
}
