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
        ListenResumePointStore.shared.save(article: key, paragraph: iAfter)
        // A crash-resume target read at coordinator init (before migration) — old numbering.
        coordinator.pendingResume = ListenResumeTarget(articleKey: key.uuidString, paragraph: iAfter, at: Date())

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

    func testLinksWithoutTextAreSkipped() throws {
        let link = library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: library.favorites())
        XCTAssertEqual(link.listenBlocksVersion, 0)
        XCTAssertEqual(library.migrateParagraphLayout().articles, 0)
        XCTAssertFalse(link.hasText)
    }
}
