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
        let book = record([.done, .done, .queued, .failed, .failed])
        let keys = book.entries.map(\.key)
        var voices = [keys[0]: heart, keys[1]: bella, keys[2]: heart, keys[3]: heart, keys[4]: heart]
        func prepared(_ k: [UUID], current: String? = "kokoro.af_heart") -> Bool {
            PrepareOverview.isPrepared(k, records: [book], currentVoice: current) { voices[$0] }
        }
        XCTAssertTrue(prepared([keys[0]]))
        XCTAssertFalse(prepared([keys[1]]), "done, but in another voice")
        XCTAssertFalse(prepared([keys[2]]), "still queued")
        XCTAssertFalse(prepared([keys[3]]), "can't be read (its language): nothing prepared")
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

    /// A prepare list written while Apple's voices read other languages still loads (one unknown
    /// state would lose every prepare): such a page is queued again, and its turn decides it.
    func testAPageOnceSpokenLiveIsQueuedAgain() throws {
        let json = #"{"key":"\#(UUID().uuidString)","state":"speaksLive"}"#
        let entry = try JSONDecoder().decode(PrepareRecord.Entry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.state, .queued)
        XCTAssertThrowsError(try JSONDecoder().decode(PrepareRecord.Entry.self,
                                                      from: Data(#"{"key":"\#(UUID().uuidString)","state":"x"}"#.utf8)))
    }

    func testAudioInAnotherVoiceIsADifferentVoice() {
        let mixed = record([.done, .done, .failed, .failed])
        let o = overview([mixed], voices: [mixed.entries[0].key: heart, mixed.entries[1].key: bella])
        XCTAssertEqual(o.differentVoice.first?.status, .differentVoice(bella))
        XCTAssertEqual(o.differentVoice.first?.voice, bella)
        XCTAssertTrue(o.done.isEmpty)
    }

    /// C138: each article renders in its own voice, so its audio counts as prepared in that voice
    /// whatever the voice in Settings; audio not in its own voice never does.
    func testEachArticleIsPreparedInItsOwnVoice() {
        let two = record([.done, .done])
        let (a, b) = (two.entries[0].key, two.entries[1].key)
        let own = [a: heart, b: bella]
        XCTAssertTrue(PrepareOverview.isPrepared([a, b], records: [two], currentVoiceOf: { own[$0] }) { own[$0] })
        XCTAssertFalse(PrepareOverview.isPrepared([b], records: [two], currentVoiceOf: { own[$0] }) { _ in self.heart },
                       "audio in another voice than the article's")
        let o = PrepareArticles(records: [two], active: nil, currentVoiceOf: { own[$0] }, rendersPreparedAudio: true) { own[$0] }
        XCTAssertEqual(o.done.map(\.voice), [heart, bella], "each row named by its own voice")
        XCTAssertTrue(o.differentVoice.isEmpty)
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

    /// Phonon's cache voice keys carry its model revision: audio another model rendered never
    /// plays or counts as prepared, and the launch migration gives audio from before the revision
    /// the revision that rendered it (`PhononCacheRevision.legacyRevision`), not the current one.
    @MainActor
    func testAudioOfAnotherModelRevisionNeverCountsAsPrepared() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "revision-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let cache = ArticleAudioCache(root: root)
        let paragraphs = ["One sentence.", "Another sentence."]
        let engine = SpeechEngineID.phonon.rawValue
        let current = try XCTUnwrap(PhononProvider.descriptor.cacheVoiceID(engineVoice: "Zoey"))
        let plans = ChunkPlans { _ in .phonon }
        func render(_ voice: String) throws -> UUID {
            let key = UUID()
            try fm.createDirectory(at: cache.directory(for: key), withIntermediateDirectories: true)
            for i in paragraphs.indices {
                try Data(count: 1024).write(to: cache.paragraphFileURL(articleID: key, paragraphIndex: i))
                try cache.recordParagraph(articleID: key, paragraphIndex: i, duration: 1, engineID: engine, voiceID: voice,
                                          textHash: ArticleIdentity.paragraphHash(paragraphs[i]), chunkDurations: nil)
            }
            return key
        }
        func missing(_ key: UUID, in voice: String? = nil) -> [Int] {
            cache.missingParagraphs(articleID: key, paragraphs: paragraphs, engineID: engine,
                                    voiceID: voice ?? current, plans: plans)
        }

        XCTAssertTrue(current.hasPrefix("phonon@\(PhononModelStore.bundleBuilt)."), current)
        let rendered = try render(current)
        let otherModel = try render("phonon@1.Zoey")
        let beforeRevisions = try render("phonon.Zoey")
        XCTAssertEqual(missing(rendered), [])
        XCTAssertEqual(missing(otherModel), [0, 1], "another model's audio")
        XCTAssertNil(cache.playableAudioURL(articleID: otherModel, paragraphIndex: 0, engineID: engine, voiceID: current))
        XCTAssertEqual(missing(beforeRevisions), [0, 1], "no revision is not this one")

        XCTAssertNotEqual(PhononCacheRevision.legacyRevision, "phonon@\(PhononModelStore.bundleBuilt)")
        XCTAssertEqual(cache.renameVoices(PhononCacheRevision.renamed).articles, 1)
        XCTAssertEqual(missing(beforeRevisions, in: PhononCacheRevision.legacyRevision + ".Zoey"), [],
                       "migrated to the revision that rendered it")
        XCTAssertEqual(missing(beforeRevisions), [0, 1], "an older bundle's audio is not this bundle's")
        XCTAssertEqual(missing(otherModel), [0, 1], "the migration never adopts another revision")
        XCTAssertEqual(missing(rendered), [])
    }
}
