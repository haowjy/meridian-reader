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
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for i in paragraphs.indices {
                let staged = root.appending(path: "staged-\(UUID().uuidString).caf")
                try Data(count: 1024).write(to: staged)
                try cache.publishParagraph(staged: staged, articleID: key, paragraphIndex: i, duration: 1, engineID: engine,
                                           voiceID: voice, textHash: ArticleIdentity.paragraphHash(paragraphs[i]),
                                           chunkDurations: nil)
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

    // MARK: - Old voices (voice-retention.md)

    private typealias Voice = ArticleAudioCache.CacheVoice
    private let zoey = Voice(engineID: SpeechEngineID.phonon.rawValue, voiceID: "phonon@test.Zoey")
    private let alba = Voice(engineID: SpeechEngineID.phonon.rawValue, voiceID: "phonon@test.Alba")
    private let text = ["First sentence here.", "Second sentence here.", "Third sentence here."]

    /// A cache in a temp directory, with what the tests ask of it.
    @MainActor
    private final class VoiceCache {
        let root = FileManager.default.temporaryDirectory.appending(path: "voices-\(UUID().uuidString)")
        private(set) var cache: ArticleAudioCache
        let plans = ChunkPlans { _ in .phonon }

        init() throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            cache = ArticleAudioCache(root: root)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A new process over the same files: nothing in memory.
        func relaunch() { cache = ArticleAudioCache(root: root) }

        func publish(_ key: UUID, _ paragraphs: [String], _ indices: [Int], in voice: Voice) throws {
            for i in indices {
                let staged = root.appending(path: "staged-\(UUID().uuidString).caf")
                try Data(count: 1024).write(to: staged)
                try cache.publishParagraph(staged: staged, articleID: key, paragraphIndex: i, duration: 1,
                                           engineID: voice.engineID, voiceID: voice.voiceID,
                                           textHash: ArticleIdentity.paragraphHash(paragraphs[i]), chunkDurations: nil)
            }
        }

        func missing(_ key: UUID, _ paragraphs: [String], in voice: Voice) -> [Int] {
            cache.missingParagraphs(articleID: key, paragraphs: paragraphs, engineID: voice.engineID,
                                    voiceID: voice.voiceID, plans: plans)
        }

        /// The voice record's run; true when its postcondition holds.
        @discardableResult
        func settle(_ key: UUID, _ paragraphs: [String], in voice: Voice) throws -> Bool {
            try cache.settleVoice(key, in: voice, paragraphs: paragraphs, kind: .saved) { self.plans.chunks(for: $1, engineID: $0) }
            return cache.isVoiceSettled(key, in: voice, kind: .saved)
        }
    }

    /// An old voice never counts as prepared or plays; changing back makes it the article's
    /// audio again, whole, with no render; a partly rendered voice comes back partly.
    @MainActor
    func testAnOldVoiceNeverCountsAndComesBackOnTheChangeBack() throws {
        let v = try VoiceCache()
        let key = UUID()
        try v.publish(key, text, [0, 1, 2], in: zoey)
        XCTAssertTrue(try v.settle(key, text, in: zoey))

        XCTAssertTrue(try v.settle(key, text, in: alba))
        XCTAssertEqual(v.missing(key, text, in: alba), [0, 1, 2])
        XCTAssertEqual(v.missing(key, text, in: zoey), [0, 1, 2], "kept as an entry, not the article's audio")
        XCTAssertNil(v.cache.playableAudioURL(articleID: key, paragraphIndex: 0, engineID: zoey.engineID, voiceID: zoey.voiceID))
        XCTAssertEqual(v.cache.oldVoices(of: key).count, 1)
        XCTAssertEqual(v.cache.cachedArticleKeys(), [], "the live directory holds no audio")

        try v.publish(key, text, [0], in: alba)
        XCTAssertTrue(try v.settle(key, text, in: zoey))
        XCTAssertEqual(v.missing(key, text, in: zoey), [], "back whole")
        XCTAssertEqual(v.missing(key, text, in: alba), [0, 1, 2])
        XCTAssertNotNil(v.cache.playableAudioURL(articleID: key, paragraphIndex: 2, engineID: zoey.engineID, voiceID: zoey.voiceID))

        v.relaunch()
        XCTAssertTrue(try v.settle(key, text, in: alba))
        XCTAssertEqual(v.missing(key, text, in: alba), [1, 2], "the paragraph it had comes back, the rest is missing")
        XCTAssertEqual(v.cache.oldVoices(of: key).count, 1, "at most one entry per voice")
    }

    /// A paragraph whose text changed while its voice was away is missing after the change back.
    @MainActor
    func testAParagraphWhoseTextChangedMeanwhileIsMissingAfterTheRestore() throws {
        let v = try VoiceCache()
        let key = UUID()
        try v.publish(key, text, [0, 1, 2], in: zoey)
        try v.settle(key, text, in: alba)
        var edited = text
        edited[1] = "A revised second sentence."
        XCTAssertTrue(try v.settle(key, edited, in: zoey))
        XCTAssertEqual(v.missing(key, edited, in: zoey), [1])
    }

    /// A render in the new voice before the record ran (it failed, with the old voice's index in
    /// memory) archives the old voice first; the record then finishes, and nothing mixes or is lost.
    @MainActor
    func testAPublishInAnotherVoiceArchivesTheOldOneFirst() throws {
        let v = try VoiceCache()
        let key = UUID()
        try v.publish(key, text, [0, 1, 2], in: zoey)
        XCTAssertEqual(v.missing(key, text, in: zoey), [], "zoey's index warm in memory")
        try v.publish(key, text, [0], in: alba) // the record for alba hasn't run
        XCTAssertEqual(v.cache.audioVoice(of: key), alba)
        XCTAssertEqual(v.missing(key, text, in: alba), [1, 2])
        XCTAssertEqual(v.missing(key, text, in: zoey), [0, 1, 2], "zoey never counts in alba's directory")
        XCTAssertTrue(try v.settle(key, text, in: alba))
        XCTAssertEqual(v.missing(key, text, in: alba), [1, 2])

        // Back to zoey; its record fails, a render publishes zoey's paragraph 1, then the record runs.
        try v.publish(key, text, [1], in: zoey)
        XCTAssertEqual(v.missing(key, text, in: zoey), [0, 2])
        XCTAssertTrue(try v.settle(key, text, in: zoey))
        XCTAssertEqual(v.missing(key, text, in: zoey), [], "the entry fills in what was published since")
        XCTAssertEqual(v.cache.oldVoices(of: key).count, 1, "alba's, and no entry of zoey")
    }

    /// `settleVoice` from the state after each single write, rename and delete of an interrupted
    /// change ends in the invariant, across a relaunch, without losing the kept voice.
    @MainActor
    func testAnInterruptedChangeFinishesFromEveryStep() throws {
        let v = try VoiceCache()
        let fm = FileManager.default
        func fresh() throws -> UUID {
            let key = UUID()
            try v.publish(key, text, [0, 1, 2], in: zoey)
            try v.cache.markSaved(cacheKey: key)
            return key
        }
        func marked(_ key: UUID) throws {
            var meta = try XCTUnwrap(v.cache.loadMeta(for: key))
            meta.voiceOf = key
            meta.kind = .ephemeral
            try v.cache.writeMeta(meta, for: key)
        }
        func check(_ key: UUID, _ step: String) throws {
            v.relaunch()
            XCTAssertTrue(try v.settle(key, text, in: alba), step)
            XCTAssertEqual(v.cache.loadMeta(for: key)?.kind, .saved, step)
            XCTAssertTrue(try v.settle(key, text, in: zoey), step)
            XCTAssertEqual(v.missing(key, text, in: zoey), [], "\(step): zoey kept")
            XCTAssertEqual(v.cache.oldVoices(of: key).count, 0, step)
        }

        let marks = try fresh()
        try marked(marks)
        try check(marks, "ownership written, not renamed")

        let renamed = try fresh()
        try marked(renamed)
        try fm.moveItem(at: v.cache.directory(for: renamed), to: v.cache.directory(for: UUID()))
        try check(renamed, "renamed, live directory not created again")

        // Back from alba to zoey: zoey's entry, and the live directory empty (alba had no audio).
        let empty = try fresh()
        try v.settle(empty, text, in: alba)
        v.relaunch()
        XCTAssertTrue(try v.settle(empty, text, in: zoey), "an empty live directory in the way")
        XCTAssertEqual(v.missing(empty, text, in: zoey), [])

        let deleted = try fresh()
        try v.settle(deleted, text, in: alba)
        try fm.removeItem(at: v.cache.directory(for: deleted))
        v.relaunch()
        XCTAssertTrue(try v.settle(deleted, text, in: zoey), "live directory deleted, entry not renamed")
        XCTAssertEqual(v.missing(deleted, text, in: zoey), [])

        let restored = try fresh()
        try marked(restored)
        v.relaunch()
        XCTAssertTrue(try v.settle(restored, text, in: zoey), "zoey live, still carrying voiceOf and the wrong kind")
        XCTAssertNil(v.cache.loadMeta(for: restored)?.voiceOf)
        XCTAssertEqual(v.missing(restored, text, in: zoey), [])
    }

    /// A merge of two keys in different voices leaves one voice live; the other is kept as an
    /// entry of the kept key.
    @MainActor
    func testAMergeOfTwoVoicesLeavesOneVoiceLive() throws {
        let v = try VoiceCache()
        for voice in [zoey, alba] {
            let (kept, merged) = (UUID(), UUID())
            try v.publish(kept, text, [0, 1], in: zoey)
            try v.publish(merged, text, [2], in: alba)
            try v.cache.reconcile(articleID: kept, paragraphs: text, adopting: merged, voice: voice)
            XCTAssertFalse(v.cache.hasDirectory(for: merged))
            XCTAssertEqual(v.cache.audioVoice(of: kept), voice)
            XCTAssertEqual(v.missing(kept, text, in: voice), voice == zoey ? [2] : [0, 1])
            XCTAssertEqual(v.cache.oldVoices(of: kept).count, 1, "the other voice kept")
        }
    }
}
