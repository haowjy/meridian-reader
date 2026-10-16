import AVFoundation
import XCTest
@testable import MeridianReader

/// A unit the player can't sound (`play()` refused, a decode error) leaves the player as done, and
/// the next unit plays: nothing sits as the current unit with no audio. Units are long tones that
/// never end on their own during a test.
@MainActor
final class ChunkPlaybackQueueTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func tearDown() {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    private func tone() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).caf")
        tempFiles.append(url)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: 30, sampleRate: 24_000), sampleRate: 24_000, to: url)
        return url
    }

    private func item(_ paragraph: Int, _ url: URL) -> ChunkPlaybackQueue.Item {
        .init(paragraphIndex: paragraph, fileURL: url, source: .baked, duration: 30)
    }

    /// A player whose `play()` fails, as one built before a media-services reset does.
    private final class RefusingPlayer: AVAudioPlayer {
        override func play() -> Bool { false }
    }

    func testAUnitThatWontPlayIsDroppedAndTheNextPlays() throws {
        let refused = try tone()
        let queue = ChunkPlaybackQueue(maxBuffered: 8) { url in
            url == refused ? try RefusingPlayer(contentsOf: url) : try AVAudioPlayer(contentsOf: url)
        }
        defer { queue.clear() }
        var errors = 0
        var done: [Int] = []
        var started: [Int] = []
        queue.onError = { _ in errors += 1 }
        queue.onItemDone = { done.append($0.paragraphIndex) }
        queue.onUnitStarted = { started.append($0.paragraphIndex) }

        queue.pause()
        queue.enqueue(item(0, refused))
        queue.enqueue(item(1, try tone()))
        queue.resume()

        XCTAssertEqual(errors, 1)
        XCTAssertEqual(done, [0], "the unit that wouldn't play left the player")
        XCTAssertEqual(started, [1], "only a unit that sounds is announced")
        XCTAssertEqual(queue.currentParagraphIndex, 1)
        XCTAssertTrue(queue.isAudible)
    }

    func testADecodeErrorDropsTheUnitPlaying() throws {
        var made: [AVAudioPlayer] = []
        let queue = ChunkPlaybackQueue(maxBuffered: 8) { url in
            let player = try AVAudioPlayer(contentsOf: url)
            made.append(player)
            return player
        }
        defer { queue.clear() }
        var done: [Int] = []
        queue.onItemDone = { done.append($0.paragraphIndex) }
        queue.enqueue(item(0, try tone()))
        queue.enqueue(item(1, try tone()))
        XCTAssertEqual(queue.currentParagraphIndex, 0)

        queue.audioPlayerDecodeErrorDidOccur(made[0], error: NSError(domain: "test", code: 1))

        XCTAssertEqual(done, [0])
        XCTAssertEqual(queue.currentParagraphIndex, 1, "the next unit plays")
        XCTAssertTrue(queue.isAudible)
    }
}
