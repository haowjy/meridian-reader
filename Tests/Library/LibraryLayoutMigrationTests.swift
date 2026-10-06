import AVFoundation
import SwiftData
import XCTest
@testable import Reader

/// Paragraph layout v3 on library pages: giant paragraphs split, the position kept on the same
/// sentence, cached audio sliced or moved where it still lines up, crash resume remapped.
/// Fixture text is public domain (`ParagraphSplitTests.chapterHTML`).
@MainActor
final class LibraryLayoutMigrationTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    /// A stitched paragraph CAF like the queue writes: chunk k = `lengths[k]` samples of value k+1.
    private func writeStitched(_ cache: ArticleAudioCache, article: UUID, index: Int, text: String,
                               lengths: [Int]) throws {
        var samples: [Float] = []
        for (k, n) in lengths.enumerated() { samples += [Float](repeating: Float(k + 1) / 100, count: n) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: tmp)
        try cache.storeParagraph(articleID: article, paragraphIndex: index, sourceURL: tmp,
                                 duration: Double(samples.count) / 24_000, engineID: SpeechEngineID.kokoro.rawValue,
                                 voiceID: "kstub:af_heart", text: text,
                                 chunkDurations: lengths.count > 1 ? lengths.map { Double($0) / 24_000 } : nil)
    }

    private func int16Samples(_ url: URL) throws -> [Int16] {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        return Array(UnsafeBufferPointer(start: b.int16ChannelData![0], count: Int(b.frameLength)))
    }

    func testPageMigrationKeepsPositionAndOnlyInvalidatesSplitAudio() throws {
        let coordinator = env.tts
        let cache = env.cache
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let iGiant = oldList.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let first = iGiant + 1 // the opening paragraph's split shifts the giant's first piece by one
        let oldGiant = oldList.paragraphs[iGiant] as NSString
        let offset = oldList.utf16Ranges[iGiant].location + oldGiant.range(of: "The head had been beaten").location

        let key = UUID()
        let page = Page(key: key, title: title, byline: "example.com",
                        urlString: "https://example.com/classics/boscombe-valley", contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.positionParagraph = iGiant
        page.positionUTF16 = offset
        page.listenBlocksData = try JSONEncoder().encode(oldList.paragraphs)
        page.listenBlocksVersion = 2
        page.paragraphCount = oldList.count
        env.context.insert(page)
        try env.context.save()

        // Audio as rendered before the split: the giant, the paragraph after it and the last one.
        let giantPlan = TextChunker.chunks(for: oldList.paragraphs[iGiant], limits: .kokoroCPU)
        let lengths = giantPlan.indices.map { 2400 + 240 * $0 }
        try writeStitched(cache, article: key, index: iGiant, text: oldList.paragraphs[iGiant], lengths: lengths)
        let iAfter = iGiant + 1
        try writeStitched(cache, article: key, index: iAfter, text: oldList.paragraphs[iAfter], lengths: [4800])
        let iLast = oldList.count - 1
        try writeStitched(cache, article: key, index: iLast, text: oldList.paragraphs[iLast], lengths: [4800])
        // The resume point in the text that played, old layout and numbering.
        let played = ArticleIdentity.contentFingerprint(paragraphs: oldList.paragraphs)
        ListenResumePointStore.shared.save(article: key, paragraph: iAfter, text: played)
        // A crash-resume target read at coordinator init (before migration) — old numbering.
        coordinator.pendingResume = ListenResumeTarget(articleKey: key.uuidString, paragraph: iAfter, text: played, at: Date())

        let report = library.migrateParagraphLayout()
        XCTAssertEqual(report.articles, 1)
        XCTAssertEqual(report.newParagraphs, report.oldParagraphs + 5)
        XCTAssertEqual(report.splitParagraphs, 3)

        let new = page.listenDocument()
        XCTAssertEqual(page.listenBlocksVersion, ListenHTMLBlocks.version)
        XCTAssertEqual(new.paragraphs, ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs)
        XCTAssertEqual(page.paragraphCount, new.count, "the paragraph count follows the new blocks")
        // Position: same sentence ("The head had been beaten…" starts the giant's third piece).
        XCTAssertEqual(page.positionParagraph, first + 2)
        XCTAssertTrue(new.paragraphs[page.positionParagraph].hasPrefix("The head had been beaten"))
        XCTAssertEqual(page.positionUTF16, new.utf16Ranges[first + 2].location)
        // Crash-resume point follows its paragraph.
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, iAfter + 3)
        XCTAssertEqual(coordinator.pendingResume?.paragraph, iAfter + 3, "in-memory crash target remapped too")
        // In the text the page holds now, so crash resume applies them.
        XCTAssertTrue(library.holds(page, text: ListenResumePointStore.shared.load()?.text))
        XCTAssertTrue(library.holds(page, text: coordinator.pendingResume?.text))

        // Unsplit paragraphs keep their audio at the shifted index.
        let entryAfter = cache.entry(articleID: key, paragraphIndex: iAfter + 3)
        XCTAssertEqual(entryAfter?.textHash, ArticleIdentity.paragraphHash(oldList.paragraphs[iAfter]))
        XCTAssertEqual(cache.entry(articleID: key, paragraphIndex: new.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(oldList.paragraphs[iLast]))
        // Split paragraph: a piece keeps audio only if its chunk plan lines up with the old chunks.
        var from = 0
        for k in 0..<3 {
            let piece = new.paragraphs[first + k]
            let plan = TextChunker.chunks(for: piece, limits: .kokoroCPU)
            var q: Int?
            var s = from
            while s + plan.count <= giantPlan.count {
                if Array(giantPlan[s..<(s + plan.count)]) == plan { q = s; break }
                s += 1
            }
            let entry = cache.entry(articleID: key, paragraphIndex: first + k)
            guard let q else { XCTAssertNil(entry, "misaligned piece \(k) must re-render"); continue }
            from = q + plan.count
            let e = try XCTUnwrap(entry, "aligned piece \(k) keeps audio")
            XCTAssertEqual(e.textHash, ArticleIdentity.paragraphHash(piece))
            let samples = try int16Samples(cache.directory(for: key).appendingPathComponent(e.file))
            XCTAssertEqual(samples.count, lengths[q..<(q + plan.count)].reduce(0, +), "sample-exact slice")
            XCTAssertEqual(samples.first, Int16(Float(q + 1) / 100 * 32767))
            XCTAssertEqual(samples.last, Int16(Float(q + plan.count) / 100 * 32767))
        }
        XCTAssertNotNil(cache.entry(articleID: key, paragraphIndex: first), "the giant's first piece lines up with its old first chunks")
        // Idempotent.
        XCTAssertEqual(library.migrateParagraphLayout().articles, 0)
    }

    // MARK: - Legacy duplicates on different layouts

    /// Two saved rows for one address: `current` on today's listen blocks (no audio) at
    /// `currentPosition`, and `old` on the pre-split blocks with audio rendered before the split
    /// (the giant paragraph, the one after it, the last one), its position on "The head had been
    /// beaten…" inside the giant.
    private struct LegacyPair {
        let current: UUID
        let old: UUID
        let new: ParagraphDocument
        let first: Int
        let giantPlan: [String]
        let lengths: [Int]
    }

    private func legacyPair(currentPosition: (ParagraphDocument, Int) -> Int) throws -> LegacyPair {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title)
        let iGiant = oldList.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let oldGiant = oldList.paragraphs[iGiant] as NSString
        let offset = oldList.utf16Ranges[iGiant].location + oldGiant.range(of: "The head had been beaten").location

        func row(_ id: UUID, _ url: String, savedAt: Date, paragraphs: [String], version: Int,
                 position: Int, offset: Int) -> SavedArticle {
            let row = SavedArticle(id: id, urlString: url, title: title, siteDomain: "example.com", savedAt: savedAt,
                                   cleanedHTML: html, plainText: "", wordCount: 100, estimatedMinutes: 1, excerpt: "",
                                   playbackParagraphIndex: position, playbackUTF16Offset: offset)
            row.listenBlocksData = try? JSONEncoder().encode(paragraphs)
            row.listenBlocksVersion = version
            env.context.insert(row)
            return row
        }
        let current = UUID(), old = UUID()
        let p = currentPosition(new, iGiant + 1)
        _ = row(current, "https://example.com/classics/boscombe-valley", savedAt: env.now, paragraphs: new.paragraphs,
                version: ListenHTMLBlocks.version, position: p, offset: new.utf16Ranges[p].location)
        _ = row(old, "https://example.com/classics/boscombe-valley?utm_source=feed", savedAt: env.now - 100,
                paragraphs: oldList.paragraphs, version: 2, position: iGiant, offset: offset)
        try env.context.save()

        let giantPlan = TextChunker.chunks(for: oldList.paragraphs[iGiant], limits: .kokoroCPU)
        let lengths = giantPlan.indices.map { 2400 + 240 * $0 }
        try writeStitched(env.cache, article: old, index: iGiant, text: oldList.paragraphs[iGiant], lengths: lengths)
        try writeStitched(env.cache, article: old, index: iGiant + 1, text: oldList.paragraphs[iGiant + 1], lengths: [4800])
        try writeStitched(env.cache, article: old, index: oldList.count - 1, text: oldList.paragraphs[oldList.count - 1],
                          lengths: [4800])
        return LegacyPair(current: current, old: old, new: new, first: iGiant + 1, giantPlan: giantPlan, lengths: lengths)
    }

    /// The giant's pieces whose chunk plan lines up with the old chunks hold the matching slice of
    /// the old audio, sample-exact, under `key`; the others have none.
    private func assertSlicedAudio(_ pair: LegacyPair, under key: UUID, file: StaticString = #filePath, line: UInt = #line) throws {
        var from = 0
        var sliced = 0
        for k in 0..<3 {
            let piece = pair.new.paragraphs[pair.first + k]
            let plan = TextChunker.chunks(for: piece, limits: .kokoroCPU)
            var q: Int?
            var s = from
            while s + plan.count <= pair.giantPlan.count {
                if Array(pair.giantPlan[s..<(s + plan.count)]) == plan { q = s; break }
                s += 1
            }
            let entry = env.cache.entry(articleID: key, paragraphIndex: pair.first + k)
            guard let q else { XCTAssertNil(entry, "misaligned piece \(k)", file: file, line: line); continue }
            from = q + plan.count
            let e = try XCTUnwrap(entry, "aligned piece \(k) keeps its audio", file: file, line: line)
            XCTAssertEqual(e.textHash, ArticleIdentity.paragraphHash(piece), file: file, line: line)
            let samples = try int16Samples(env.cache.directory(for: key).appendingPathComponent(e.file))
            XCTAssertEqual(samples.count, pair.lengths[q..<(q + plan.count)].reduce(0, +), "sample-exact slice", file: file, line: line)
            XCTAssertEqual(samples.first, Int16(Float(q + 1) / 100 * 32767), file: file, line: line)
            XCTAssertEqual(samples.last, Int16(Float(q + plan.count) / 100 * 32767), file: file, line: line)
            sliced += 1
        }
        XCTAssertGreaterThan(sliced, 0, "some of the giant's audio is reusable", file: file, line: line)
        // The unsplit paragraph after the giant and the last one keep theirs at the shifted index.
        let shifted = pair.first + 3
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: shifted)?.textHash,
                       ArticleIdentity.paragraphHash(pair.new.paragraphs[shifted]), file: file, line: line)
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: pair.new.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(pair.new.paragraphs[pair.new.count - 1]), file: file, line: line)
    }

    /// Positions are compared on one layout: the old row's spot, inside the giant paragraph, is
    /// further on than the current row's (the giant's first piece) once both are on today's
    /// blocks, so the old row is kept, at the same sentence, with its sliced audio.
    func testMigratedDuplicatesAreComparedAfterTheLayoutPass() throws {
        let pair = try legacyPair { _, giantFirstPiece in giantFirstPiece }
        library.migrateLegacy()

        let pages = env.pages()
        XCTAssertEqual(pages.count, 1, "one page per address")
        let page = try XCTUnwrap(pages.first)
        XCTAssertEqual(page.key, pair.old, "the furthest position wins, measured on the same paragraphs")
        XCTAssertEqual(page.listenBlocksVersion, ListenHTMLBlocks.version)
        XCTAssertEqual(page.positionParagraph, pair.first + 2)
        XCTAssertTrue(pair.new.paragraphs[page.positionParagraph].hasPrefix("The head had been beaten"))
        XCTAssertEqual(page.positionUTF16, pair.new.utf16Ranges[pair.first + 2].location)
        try assertSlicedAudio(pair, under: pair.old)
    }

    /// The page on today's blocks is further on and is kept: the other's audio is aligned to
    /// the new paragraphs (sliced) before it merges in, so the reusable pieces survive.
    func testMigratedDuplicatesKeepSlicedAudioWhenTheCurrentPageWins() throws {
        let pair = try legacyPair { new, _ in new.count - 2 }
        library.migrateLegacy()

        let pages = env.pages()
        XCTAssertEqual(pages.count, 1)
        let page = try XCTUnwrap(pages.first)
        XCTAssertEqual(page.key, pair.current)
        XCTAssertEqual(page.positionParagraph, pair.new.count - 2)
        try assertSlicedAudio(pair, under: pair.current)
        XCTAssertFalse(env.cache.hasCache(for: pair.old), "merged into the kept page")
    }

    func testLinksWithoutTextAreSkipped() throws {
        let link = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: library.favorites())
        XCTAssertEqual(link.listenBlocksVersion, 0)
        XCTAssertEqual(library.migrateParagraphLayout().articles, 0)
        XCTAssertFalse(link.hasText)
    }
}
