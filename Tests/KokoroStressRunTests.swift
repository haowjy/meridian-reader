import XCTest
@testable import MeridianReader

/// The `-KokoroStress` harness's corpus and crash-resume bookkeeping (the device run itself is
/// manual).
final class KokoroStressRunTests: XCTestCase {
    func testCorpusIsFixedVariedAndSizedForOneCall() {
        let corpus = KokoroStressCorpus.chunks(count: KokoroStressCorpus.calls)
        XCTAssertEqual(corpus.count, 320)
        XCTAssertEqual(corpus, KokoroStressCorpus.chunks(count: KokoroStressCorpus.calls), "same calls every run")
        let lengths = corpus.map(\.text.count)
        XCTAssertLessThanOrEqual(lengths.max() ?? 0, TextChunker.Limits.kokoroCPU.hardMax)
        XCTAssertLessThan(lengths.min() ?? 0, 80)
        XCTAssertGreaterThan(lengths.filter { $0 >= 200 }.count, 50)
    }

    func testACallBegunAndNeverEndedIsACrashAndTheRunGoesOnAfterIt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stress-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = KokoroStressLog(url: url)
        log.append(["ev": "start", "run": "a", "corpus_calls": 3, "from": 0])
        log.append(["ev": "begin", "run": "a", "i": 0, "t": 1.0])
        log.append(["ev": "end", "run": "a", "i": 0, "ok": true, "wall_ms": 500, "audio_s": 5.0, "ms_per_audio_s": 100])
        log.append(["ev": "begin", "run": "a", "i": 1, "t": 2.0])
        let history = log.read()
        XCTAssertEqual(history.inFlight?.index, 1)
        XCTAssertEqual(history.corpusCalls, 3)

        log.append(["ev": "crash", "i": 1, "run": "a"])
        let after = log.read()
        XCTAssertNil(after.inFlight)
        XCTAssertEqual(after.nextIndex, 2)
        let summary = after.summary(route: "coreml", corpusCalls: 3, status: "complete")
        XCTAssertEqual(summary["crashes"] as? Int, 1)
        XCTAssertEqual(summary["calls_attempted"] as? Int, 2)
        XCTAssertEqual(summary["ms_per_audio_s"] as? Int, 100)
        XCTAssertEqual(summary["x_realtime"] as? Double, 10)
    }
}
