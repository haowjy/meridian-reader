import XCTest
@testable import MeridianReader

/// Every change `ArticleAudioCache` makes to an article's audio is copy-on-write: stopped at any
/// step (the fault hook throws there, as if the app died), a cold load of the cache (a new
/// instance over the same directory) finds every CAF its index lists, no rendered paragraph's
/// audio is lost, and running the change again finishes it.
@MainActor
final class ArticleAudioCacheCrashTests: XCTestCase {
    private var roots: [URL] = []
    private let engine = "local.kokoro"
    private let voice = "kokoro.af_heart"
    private struct Died: Error {}

    override func tearDown() async throws {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        roots = []
    }

    // MARK: Fixtures

    /// A rendered paragraph whose samples are all `value`, so its bytes are its own; stitched from
    /// `chunks` (sample counts) when there are several.
    @discardableResult
    private func render(_ cache: ArticleAudioCache, _ key: UUID, _ index: Int, _ text: String,
                        value: Float, chunks: [Int] = [2400]) throws -> Data {
        var samples: [Float] = []
        for (k, n) in chunks.enumerated() { samples += [Float](repeating: value + Float(k) / 1000, count: n) }
        let tmp = cache.root.appendingPathComponent("tone-\(UUID().uuidString).caf")
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: tmp)
        let url = try cache.storeParagraph(articleID: key, paragraphIndex: index, sourceURL: tmp,
                                           duration: Double(samples.count) / 24_000, engineID: engine, voiceID: voice,
                                           text: text, chunkDurations: chunks.count > 1 ? chunks.map { Double($0) / 24_000 } : nil)
        return try Data(contentsOf: url)
    }

    /// A paragraph over the split threshold made of two pieces of two sentences each; the test's
    /// chunk plan cuts at full stops, so each piece is a run of the giant's chunks.
    private let pieces: [String] = (0..<2).map { p in
        (0..<2).map { s in String(repeating: "piece\(p) sentence\(s) words ", count: 24) + "end." }.joined(separator: " ")
    }
    private var giant: String { pieces.joined(separator: " ") }
    private let chunkPlan: (String, String) -> [String]? = { _, text in
        text.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Text hash → the bytes of every CAF a cold load of `keys` lists for it.
    private func coldAudio(_ root: URL, _ keys: [UUID]) throws -> [String: [Data]] {
        let cold = ArticleAudioCache(root: root)
        var out: [String: [Data]] = [:]
        for key in keys {
            for e in cold.index(for: key)?.paragraphs ?? [] {
                out[e.textHash ?? "-", default: []].append(try Data(contentsOf: cold.directory(for: key).appendingPathComponent(e.file)))
            }
        }
        return out
    }

    /// A cold load keeps every entry the saved index lists: none of their CAFs is missing.
    private func assertColdLoadDropsNothing(_ root: URL, _ keys: [UUID], _ note: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let cold = ArticleAudioCache(root: root)
        for key in keys {
            XCTAssertEqual(cold.index(for: key)?.paragraphs.count, cold.readIndexFile(for: key)?.paragraphs.count,
                           "\(note): every CAF the saved index lists exists", file: file, line: line)
        }
    }

    /// Runs `change` once to count its steps, then for each step: a fresh fixture, the change
    /// stopped there, `interrupted` on the cold state, the change run again on a cold cache, and
    /// `finished` on that.
    private func forEachInterruption(setUp: (ArticleAudioCache) throws -> Void,
                                     change: (ArticleAudioCache) throws -> Void,
                                     interrupted: (URL, String) throws -> Void,
                                     finished: (ArticleAudioCache, String) throws -> Void,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        func fresh() throws -> ArticleAudioCache {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCrash-\(UUID().uuidString)")
            roots.append(root)
            let cache = ArticleAudioCache(root: root)
            try setUp(cache)
            return cache
        }
        let reference = try fresh()
        var steps: [ArticleAudioCache.ChangeStep] = []
        reference.faultHook = { steps.append($0) }
        try change(reference)
        reference.faultHook = nil
        try finished(ArticleAudioCache(root: reference.root), "uninterrupted")
        XCTAssertGreaterThan(steps.count, 1, "the change has steps to stop at", file: file, line: line)

        for (k, step) in steps.enumerated() {
            let cache = try fresh()
            var seen = 0
            cache.faultHook = { _ in
                if seen == k { throw Died() }
                seen += 1
            }
            XCTAssertThrowsError(try change(cache), "stops at step \(k) (\(step))", file: file, line: line)
            let note = "died at step \(k) (\(step))"
            try interrupted(cache.root, note)
            let relaunched = ArticleAudioCache(root: cache.root)
            try change(relaunched)
            try finished(ArticleAudioCache(root: cache.root), note)
        }
    }

    // MARK: Tests

    /// A page's paragraphs changed: B and C swapped places, X was removed, and a giant paragraph
    /// was split in two. Its audio is aligned (A stays, B and C move, the giant is sliced, X and
    /// the giant are dropped) without losing a paragraph, wherever the app dies.
    func testAligningLosesNoAudioWhereverItStops() throws {
        let key = UUID()
        let old = ["A.", giant, "B.", "X.", "C."]
        let new = ["A.", pieces[0], pieces[1], "C.", "B."]
        var bytes: [String: Data] = [:]
        let setUp = { (cache: ArticleAudioCache) in
            for (i, text) in old.enumerated() {
                let chunks = text == self.giant ? [2400, 2640, 2880, 3120] : [2400]
                bytes[text] = try self.render(cache, key, i, text, value: Float(i + 1) / 10, chunks: chunks)
            }
        }
        try forEachInterruption(setUp: setUp, change: { cache in
            try cache.reconcile(articleID: key, paragraphs: new, chunkPlan: chunkPlan)
        }, interrupted: { root, note in
            assertColdLoadDropsNothing(root, [key], note)
            let audio = try coldAudio(root, [key])
            for text in ["A.", "B.", "C."] {
                XCTAssertTrue(audio[ArticleIdentity.paragraphHash(text)]?.contains(bytes[text]!) == true, "\(note): \(text) kept")
            }
            let giantKept = audio[ArticleIdentity.paragraphHash(giant)]?.contains(bytes[giant]!) == true
            let piecesKept = pieces.allSatisfy { audio[ArticleIdentity.paragraphHash($0)] != nil }
            XCTAssertTrue(giantKept || piecesKept, "\(note): the giant, or both its slices")
        }, finished: { cache, note in
            assertColdLoadDropsNothing(cache.root, [key], note)
            XCTAssertTrue(cache.isAligned(articleID: key, paragraphs: new), note)
            let index = try XCTUnwrap(cache.index(for: key), note)
            XCTAssertEqual(index.paragraphs.map(\.index), [0, 1, 2, 3, 4], note)
            XCTAssertEqual(index.paragraphs.map(\.textHash), new.map(ArticleIdentity.paragraphHash), note)
            guard index.paragraphs.count == new.count else { return }
            for (i, text) in new.enumerated() where bytes[text] != nil {
                let e = index.paragraphs[i]
                XCTAssertEqual(try Data(contentsOf: cache.directory(for: key).appendingPathComponent(e.file)), bytes[text], "\(note): \(text)")
            }
            XCTAssertEqual(index.paragraphs[1].chunkDurations, [2400, 2640].map { Double($0) / 24_000 }, note)
            XCTAssertEqual(index.paragraphs[2].chunkDurations, [2880, 3120].map { Double($0) / 24_000 }, note)
            // Copies an interrupted run wrote and never listed are gone. (A `p-` file the index
            // stopped listing just before the app died stays until that paragraph re-renders.)
            let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory(for: key).path)
            let listed = Set(index.paragraphs.map(\.file))
            XCTAssertEqual(files.filter { ($0.hasPrefix("m-") || $0.hasPrefix("s-")) && !listed.contains($0) }, [], note)
            if note == "uninterrupted" {
                XCTAssertEqual(Set(files.filter { $0.hasSuffix(".caf") }), listed, "\(note): only the listed CAFs remain")
            }
        })
    }

    /// Dedupe merged page F into T: F's audio fills the paragraphs T has none for (T's own unit
    /// wins where both have one), then F's directory goes. Wherever the app dies, every unit T
    /// ends up with is under T or still under F.
    func testAdoptingAMergedArticlesAudioLosesNothingWhereverItStops() throws {
        let t = UUID(), f = UUID()
        let paragraphs = ["A.", "B.", "C.", "D."]
        var tBytes: [String: Data] = [:], fBytes: [String: Data] = [:]
        let setUp = { (cache: ArticleAudioCache) in
            for (i, text) in ["A.", "B."].enumerated() { tBytes[text] = try self.render(cache, t, i, text, value: 0.1 + Float(i) / 10) }
            for (i, text) in ["A.", "C.", "D.", "Z."].enumerated() { fBytes[text] = try self.render(cache, f, i, text, value: 0.5 + Float(i) / 10) }
        }
        try forEachInterruption(setUp: setUp, change: { cache in
            try cache.reconcile(articleID: t, paragraphs: paragraphs, adopting: f, chunkPlan: chunkPlan)
        }, interrupted: { root, note in
            assertColdLoadDropsNothing(root, [t, f], note)
            let audio = try coldAudio(root, [t, f])
            for (text, source) in [("A.", tBytes), ("B.", tBytes), ("C.", fBytes), ("D.", fBytes)] {
                XCTAssertTrue(audio[ArticleIdentity.paragraphHash(text)]?.contains(source[text]!) == true, "\(note): \(text)")
            }
        }, finished: { cache, note in
            assertColdLoadDropsNothing(cache.root, [t], note)
            XCTAssertTrue(cache.isAligned(articleID: t, paragraphs: paragraphs), note)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory(for: f).path), "\(note): F's directory is gone")
            let index = try XCTUnwrap(cache.index(for: t), note)
            XCTAssertEqual(index.paragraphs.map(\.textHash), paragraphs.map(ArticleIdentity.paragraphHash), note)
            guard index.paragraphs.count == paragraphs.count else { return }
            for (i, text) in paragraphs.enumerated() {
                let want = text == "A." || text == "B." ? tBytes[text] : fBytes[text]
                XCTAssertEqual(try Data(contentsOf: cache.directory(for: t).appendingPathComponent(index.paragraphs[i].file)), want, "\(note): \(text)")
            }
        })
    }

    /// Save of a legacy reader key onto a key that already has a directory: the units it lacks
    /// (by paragraph) are copied in, then the old key's directory goes.
    func testRekeyingOntoAnExistingDirectoryLosesNothingWhereverItStops() throws {
        let saved = UUID(), reader = UUID()
        var savedBytes = Data(), readerBytes: [Data] = []
        let setUp = { (cache: ArticleAudioCache) in
            savedBytes = try self.render(cache, saved, 0, "A.", value: 0.1)
            readerBytes = [try self.render(cache, reader, 0, "A.", value: 0.5), try self.render(cache, reader, 1, "B.", value: 0.6)]
        }
        try forEachInterruption(setUp: setUp, change: { cache in
            try cache.rekeyCache(from: reader, to: saved)
        }, interrupted: { root, note in
            assertColdLoadDropsNothing(root, [saved, reader], note)
            let audio = try coldAudio(root, [saved, reader])
            XCTAssertTrue(audio[ArticleIdentity.paragraphHash("A.")]?.contains(savedBytes) == true, note)
            XCTAssertTrue(audio[ArticleIdentity.paragraphHash("B.")]?.contains(readerBytes[1]) == true, note)
        }, finished: { cache, note in
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory(for: reader).path), note)
            let index = try XCTUnwrap(cache.index(for: saved), note)
            XCTAssertEqual(index.paragraphs.map(\.index), [0, 1], note)
            guard index.paragraphs.count == 2 else { return }
            XCTAssertEqual(try Data(contentsOf: cache.directory(for: saved).appendingPathComponent(index.paragraphs[0].file)), savedBytes, note)
            XCTAssertEqual(try Data(contentsOf: cache.directory(for: saved).appendingPathComponent(index.paragraphs[1].file)), readerBytes[1], note)
            XCTAssertEqual(cache.loadMeta(for: saved)?.kind, .saved, note)
        })
    }

    /// A key with no directory takes the old one whole, in one rename.
    func testRekeyingOntoANewKeyIsOneRename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCrash-\(UUID().uuidString)")
        roots.append(root)
        let cache = ArticleAudioCache(root: root)
        let reader = UUID(), saved = UUID()
        let bytes = try render(cache, reader, 0, "A.", value: 0.3)
        var steps: [ArticleAudioCache.ChangeStep] = []
        cache.faultHook = { steps.append($0); throw Died() }
        XCTAssertThrowsError(try cache.rekeyCache(from: reader, to: saved))
        XCTAssertEqual(steps, [.movedDirectory])
        XCTAssertEqual(try coldAudio(root, [saved])[ArticleIdentity.paragraphHash("A.")], [bytes], "all of it under the new key")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory(for: reader).path))
    }

    /// A saved index can list a CAF that has gone (an older build's crash): aligning rewrites the
    /// index without it, so its postcondition holds.
    func testAligningDropsEntriesWhoseFileIsGoneFromTheSavedIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCrash-\(UUID().uuidString)")
        roots.append(root)
        let cache = ArticleAudioCache(root: root)
        let key = UUID()
        try render(cache, key, 0, "A.", value: 0.1)
        try render(cache, key, 1, "B.", value: 0.2)
        try FileManager.default.removeItem(at: cache.directory(for: key).appendingPathComponent("p-0001.caf"))
        let cold = ArticleAudioCache(root: root)
        XCTAssertFalse(cold.isAligned(articleID: key, paragraphs: ["A.", "B."]))
        try cold.reconcile(articleID: key, paragraphs: ["A.", "B."])
        XCTAssertTrue(cold.isAligned(articleID: key, paragraphs: ["A.", "B."]))
        XCTAssertEqual(cold.readIndexFile(for: key)?.paragraphs.map(\.index), [0])
    }
}
