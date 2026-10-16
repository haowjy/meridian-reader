import XCTest
@testable import MeridianReader

/// What the Downloads list and the progress line show (decision D16), from the list alone.
final class DownloadOverviewTests: XCTestCase {
    private let heart = "kokoro.af_heart"
    private let bella = "kokoro.af_bella"

    private func record(_ states: [DownloadRecord.PageState], paused: Bool = false, kept: String? = nil) -> DownloadRecord {
        var record = DownloadRecord(target: .folder(UUID()), title: "Book", addedAt: Date(),
                                    entries: states.map { DownloadRecord.Entry(key: UUID(), state: $0) })
        record.isPaused = paused
        record.keptVoice = kept
        return record
    }

    private func overview(_ records: [DownloadRecord], active: DownloadOverview.Active? = nil, current: String? = "kokoro.af_heart",
                          renders: Bool = true, voices: [UUID: String] = [:]) -> DownloadOverview {
        DownloadOverview(records: records, active: active, currentVoice: current, rendersDownloads: renders) { voices[$0] }
    }

    func testQueuedDownloadsCountFinishedPagesAndThePageRendering() throws {
        let book = record([.done, .queued, .queued, .queued])
        let o = overview([book], active: .init(recordID: book.id, key: book.entries[1].key, fraction: 0.5))
        XCTAssertEqual(o.queued.first?.status, .downloading(fraction: 1.5 / 4))
        XCTAssertEqual(o.queued.first?.voice, heart, "named by the voice it renders in")
        XCTAssertEqual(try XCTUnwrap(o.progress), 1.5 / 4, accuracy: 1e-9)
        let fetching = overview([book], active: .init(recordID: book.id, key: book.entries[1].key, fraction: 0, isFetching: true))
        XCTAssertEqual(fetching.queued.first?.status, .fetching(fraction: 1.0 / 4), "a link page's text is being fetched")
    }

    func testTheLineCoversOnlyRunningDownloads() throws {
        let running = record([.done, .queued])
        let paused = record([.queued, .queued], paused: true)
        let o = overview([running, paused])
        XCTAssertEqual(o.queued.map(\.status), [.queued(fraction: 0.5), .paused(fraction: 0)])
        XCTAssertEqual(try XCTUnwrap(o.progress), 0.5, accuracy: 1e-9)
        XCTAssertNil(overview([paused]).progress, "everything paused: no line")
        XCTAssertNil(overview([running], renders: false).progress, "no voice renders downloads: no line")
        XCTAssertEqual(overview([running], renders: false).queued.first?.status, .waitingForVoice(fraction: 0.5))
        XCTAssertNil(overview([record([.done, .failed])]).progress, "nothing queued: no line")
    }

    func testDoneInTheCurrentVoiceOrAKeptOne() {
        let done = record([.done, .done])
        let o = overview([done], voices: [done.entries[0].key: heart, done.entries[1].key: heart])
        XCTAssertEqual(o.done.map(\.status), [.done])
        XCTAssertEqual(o.done.first?.voice, heart)

        let other = record([.done], kept: bella)
        let kept = overview([other], voices: [other.entries[0].key: bella])
        XCTAssertEqual(kept.done.first?.voice, bella, "kept: done, named by its own voice")
        XCTAssertTrue(kept.differentVoice.isEmpty)
    }

    /// A row's Downloaded mark: done, and in the voice downloads render in now or one kept.
    func testDownloadedMeansDoneInAVoiceTheDownloadAccepts() {
        let book = record([.done, .done, .queued, .speaksLive, .failed])
        let keys = book.entries.map(\.key)
        var voices = [keys[0]: heart, keys[1]: bella, keys[2]: heart, keys[3]: heart, keys[4]: heart]
        func downloaded(_ k: [UUID], current: String? = "kokoro.af_heart") -> Bool {
            DownloadOverview.isDownloaded(k, records: [book], currentVoice: current) { voices[$0] }
        }
        XCTAssertTrue(downloaded([keys[0]]))
        XCTAssertFalse(downloaded([keys[1]]), "done, but in another voice")
        XCTAssertFalse(downloaded([keys[2]]), "still queued")
        XCTAssertFalse(downloaded([keys[3]]), "spoken live: no audio downloaded")
        XCTAssertFalse(downloaded([keys[4]]), "failed")
        XCTAssertFalse(downloaded([UUID()]), "never downloaded")
        XCTAssertFalse(downloaded([keys[0], keys[1]]), "a folder: every page it covers")
        XCTAssertFalse(downloaded([]), "nothing covered")
        XCTAssertFalse(downloaded([keys[0]], current: nil), "no on-device voice")
        voices[keys[0]] = nil
        XCTAssertFalse(downloaded([keys[0]]), "its audio deleted since")

        let kept = record([.done], kept: bella)
        XCTAssertTrue(DownloadOverview.isDownloaded([kept.entries[0].key], records: [kept], currentVoice: heart) { _ in self.bella },
                      "in the voice its download keeps")
    }

    func testAudioInAnotherVoiceIsADifferentVoice() {
        let mixed = record([.done, .done, .speaksLive, .failed])
        let o = overview([mixed], voices: [mixed.entries[0].key: heart, mixed.entries[1].key: bella])
        XCTAssertEqual(o.differentVoice.first?.status, .differentVoice(bella))
        XCTAssertEqual(o.differentVoice.first?.voice, bella)
        XCTAssertTrue(o.done.isEmpty)
    }

    func testWithNoOnDeviceVoiceNothingIsADifferentVoice() {
        let done = record([.done])
        let o = overview([done], current: nil, renders: false, voices: [done.entries[0].key: bella])
        XCTAssertEqual(o.done.first?.voice, bella)
        XCTAssertTrue(o.differentVoice.isEmpty)
    }

    func testRequeueStartsEveryPageAgain() {
        var r = record([.done, .failed], paused: true, kept: bella)
        let keys = [UUID(), UUID(), UUID()]
        r.requeue(keys)
        XCTAssertEqual(r.entries.map(\.key), keys)
        XCTAssertTrue(r.entries.allSatisfy { $0.state == .queued })
        XCTAssertFalse(r.isPaused)
        XCTAssertNil(r.keptVoice)
    }

    @MainActor
    func testVoiceLabels() {
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FluidAudioProvider()], gate: { _ in true })
        XCTAssertEqual(registry.voiceLabel(forCacheVoice: heart), "Kokoro Heart")
        XCTAssertEqual(registry.voiceLabel(forCacheVoice: "system"), "Apple")
    }
}
