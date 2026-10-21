import XCTest
@testable import MeridianReader

/// The prepare accept rule (decision D16): a page counts as prepared when its entry is done and
/// its audio is in a voice the download accepts, the voice downloads render in now or the one
/// *Keep* stored (`PrepareRecord.accepts`). Other audio is a different voice.
final class PrepareOverviewTests: XCTestCase {
    private let heart = "kokoro.af_heart"
    private let bella = "kokoro.af_bella"

    private func record(_ states: [PrepareRecord.ArticleState], kept: String? = nil) -> PrepareRecord {
        var record = PrepareRecord(target: .folder(UUID()), title: "Book", addedAt: Date(),
                                    entries: states.map { PrepareRecord.Entry(key: UUID(), state: $0) })
        record.keptVoice = kept
        return record
    }

    private func overview(_ records: [PrepareRecord], voices: [UUID: String] = [:]) -> PrepareOverview {
        PrepareOverview(records: records, active: nil, currentVoice: heart, rendersPreparedAudio: true) { voices[$0] }
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
    func testPreparedMeansDoneInAVoiceThePrepareAccepts() {
        let book = record([.done, .done, .queued, .speaksLive, .failed])
        let keys = book.entries.map(\.key)
        var voices = [keys[0]: heart, keys[1]: bella, keys[2]: heart, keys[3]: heart, keys[4]: heart]
        func prepared(_ k: [UUID], current: String? = "kokoro.af_heart") -> Bool {
            PrepareOverview.isPrepared(k, records: [book], currentVoice: current) { voices[$0] }
        }
        XCTAssertTrue(prepared([keys[0]]))
        XCTAssertFalse(prepared([keys[1]]), "done, but in another voice")
        XCTAssertFalse(prepared([keys[2]]), "still queued")
        XCTAssertFalse(prepared([keys[3]]), "spoken live: no audio downloaded")
        XCTAssertFalse(prepared([keys[4]]), "failed")
        XCTAssertFalse(prepared([UUID()]), "never downloaded")
        XCTAssertFalse(prepared([keys[0], keys[1]]), "a folder: every page it covers")
        XCTAssertFalse(prepared([]), "nothing covered")
        XCTAssertFalse(prepared([keys[0]], current: nil), "no on-device voice")
        voices[keys[0]] = nil
        XCTAssertFalse(prepared([keys[0]]), "its audio deleted since")

        let kept = record([.done], kept: bella)
        XCTAssertTrue(PrepareOverview.isPrepared([kept.entries[0].key], records: [kept], currentVoice: heart) { _ in self.bella },
                      "in the voice its download keeps")
    }

    func testAudioInAnotherVoiceIsADifferentVoice() {
        let mixed = record([.done, .done, .speaksLive, .failed])
        let o = overview([mixed], voices: [mixed.entries[0].key: heart, mixed.entries[1].key: bella])
        XCTAssertEqual(o.differentVoice.first?.status, .differentVoice(bella))
        XCTAssertEqual(o.differentVoice.first?.voice, bella)
        XCTAssertTrue(o.done.isEmpty)
    }

    /// Prepared audio.json written before C121 names an article's prepare `page`: it still decodes,
    /// and is written back under the same name.
    func testAnArticleTargetKeepsItsStoredName() throws {
        let key = UUID()
        let json = Data(#"{"page":{"_0":"\#(key.uuidString)"}}"#.utf8)
        let target = try JSONDecoder().decode(PrepareRecord.Target.self, from: json)
        XCTAssertEqual(target, .article(key))
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(target), as: UTF8.self), String(decoding: json, as: UTF8.self))
    }
}
