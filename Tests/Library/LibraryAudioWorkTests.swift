import SwiftData
import XCTest
@testable import Reader

/// Files outside the library store (the audio cache, pending renders, the crash-resume point)
/// change only after the library change they belong to is saved: a failed save leaves them as
/// they were, a launch that dies after the save finishes the work next time, and work done twice
/// moves nothing twice.
@MainActor
final class LibraryAudioWorkTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }
    override func tearDown() async throws { env.cleanUp() }

    private struct SaveFailed: Error {}
    private func date(_ days: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + days * 24 * 3600) }

    /// Two saved rows for one address, both with audio; the one dedupe merges away has a pending
    /// render and the crash-resume point.
    private struct DuplicateRows {
        let merged = UUID()
        let kept = UUID()
        let mergedText = ["Alpha one.", "Beta two.", "Gamma three."]
        let keptText = ["Alpha one.", "Beta changed.", "Gamma three."]
    }

    private func duplicateRows() throws -> DuplicateRows {
        let rows = DuplicateRows()
        env.legacyRow("https://example.com/dup?utm_source=feed", id: rows.merged, savedAt: date(0), paragraphs: rows.mergedText)
        env.legacyRow("https://example.com/dup", id: rows.kept, savedAt: date(1), paragraphs: rows.keptText, position: 2)
        try env.storeAudio(rows.merged, paragraphs: rows.mergedText)
        try env.storeAudio(rows.kept, paragraph: 1, text: "Beta changed.")
        PendingBakeJobStore.shared.enqueuePending(articleID: rows.merged, paragraphs: rows.mergedText, voiceID: "voiceA",
                                                  plan: .topDown(paragraphCount: 3))
        ListenResumePointStore.shared.save(article: rows.merged, paragraph: 1, at: date(2))
        addTeardownBlock { @MainActor in
            PendingBakeJobStore.shared.removePending(articleID: rows.merged)
            PendingBakeJobStore.shared.removePending(articleID: rows.kept)
        }
        return rows
    }

    /// Every file under a key's audio directory, by relative path.
    private func audioFiles(_ key: UUID) throws -> [String: Data] {
        let dir = env.cache.directory(for: key)
        guard let names = FileManager.default.subpaths(atPath: dir.path) else { return [:] }
        var out: [String: Data] = [:]
        for name in names {
            var isDir: ObjCBool = false
            let url = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[name] = try Data(contentsOf: url)
        }
        return out
    }

    private func pendingWork(_ env: LibraryTestEnvironment? = nil) -> [LibraryAudioWork] {
        ((try? (env ?? self.env).context.fetch(FetchDescriptor<LibraryAudioWork>())) ?? [])
    }

    /// The kept page has every paragraph's audio it can use, the merged copy's files are gone,
    /// its pending render is dropped and the crash-resume point names the kept page.
    private func assertMerged(_ rows: DuplicateRows, _ env: LibraryTestEnvironment? = nil, _ note: String = "",
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let env = env ?? self.env!
        XCTAssertEqual(env.pages().map(\.key), [rows.kept], "\(note) one page, the further one", file: file, line: line)
        for (i, text) in rows.keptText.enumerated() {
            XCTAssertEqual(env.cache.entry(articleID: rows.kept, paragraphIndex: i)?.textHash,
                           ArticleIdentity.paragraphHash(text), "\(note) paragraph \(i)", file: file, line: line)
        }
        XCTAssertFalse(env.cache.hasDirectory(for: rows.merged), note, file: file, line: line)
        XCTAssertFalse(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == rows.merged }, note, file: file, line: line)
        let resume = try XCTUnwrap(ListenResumePointStore.shared.load(), note, file: file, line: line)
        XCTAssertNotNil(env.library.page(matching: resume), "\(note) the resume point names a page that exists", file: file, line: line)
        XCTAssertEqual(resume.articleKey, rows.kept.uuidString, note, file: file, line: line)
        XCTAssertEqual(resume.paragraph, 1, note, file: file, line: line)
        XCTAssertTrue(pendingWork(env).isEmpty, "\(note) nothing left to do", file: file, line: line)
    }

    // MARK: Interrupted work

    private struct Died: Error {}

    /// A fault hook that lets `k` steps of the audio cache's changes through, then fails every
    /// later one: the app died at step `k`.
    private func dieAt(_ k: Int) -> (ArticleAudioCache.ChangeStep) throws -> Void {
        var seen = 0
        return { _ in
            if seen >= k { throw Died() }
            seen += 1
        }
    }

    /// How many steps `run` takes in the audio cache, uninterrupted, in a fresh environment.
    private func steps(of fixture: (LibraryTestEnvironment) throws -> Void,
                       _ run: (LibraryStore) -> Void) throws -> Int {
        let env = try LibraryTestEnvironment(fileBacked: true)
        defer { cleanUp(env) }
        try fixture(env)
        var count = 0
        env.cache.faultHook = { _ in count += 1 }
        run(env.library)
        XCTAssertTrue(pendingWork(env).isEmpty, "the uninterrupted run finishes")
        return count
    }

    private func cleanUp(_ env: LibraryTestEnvironment) {
        for key in env.pages().compactMap(\.key) { PendingBakeJobStore.shared.removePending(articleID: key) }
        env.cleanUp()
    }

    /// A cold load (a new cache over the same directory) finds every CAF the saved indexes list,
    /// and each `needed` rendering (text → its bytes) under one of `keys`.
    private func assertNothingLost(_ env: LibraryTestEnvironment, _ keys: [UUID], _ needed: [String: Data], _ note: String,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let cold = ArticleAudioCache(root: env.cache.root)
        var found: [String: [Data]] = [:]
        for key in keys {
            XCTAssertEqual(cold.index(for: key)?.paragraphs.count, cold.readIndexFile(for: key)?.paragraphs.count,
                           "\(note): a cold load drops nothing", file: file, line: line)
            for e in cold.index(for: key)?.paragraphs ?? [] {
                found[e.textHash ?? "-", default: []].append(try Data(contentsOf: cold.directory(for: key).appending(path: e.file)))
            }
        }
        for (text, bytes) in needed {
            XCTAssertTrue(found[ArticleIdentity.paragraphHash(text)]?.contains(bytes) == true,
                          "\(note): \(text.prefix(30)) still has its audio", file: file, line: line)
        }
    }

    private func bytes(_ env: LibraryTestEnvironment, _ key: UUID, paragraph: Int) throws -> Data? {
        guard let e = env.cache.entry(articleID: key, paragraphIndex: paragraph) else { return nil }
        return try Data(contentsOf: env.cache.directory(for: key).appending(path: e.file))
    }

    /// `duplicateRows` with every rendering its own bytes; returns what the kept page ends up
    /// with: text → the bytes it keeps.
    private func distinctDuplicateRows(_ env: LibraryTestEnvironment) throws -> (DuplicateRows, [String: Data]) {
        let rows = DuplicateRows()
        env.legacyRow("https://example.com/dup?utm_source=feed", id: rows.merged, savedAt: date(0), paragraphs: rows.mergedText)
        env.legacyRow("https://example.com/dup", id: rows.kept, savedAt: date(1), paragraphs: rows.keptText, position: 2)
        for (i, text) in rows.mergedText.enumerated() {
            try env.storeAudio(rows.merged, paragraph: i, text: text, level: 0.2 + Float(i) / 10)
        }
        try env.storeAudio(rows.kept, paragraph: 1, text: "Beta changed.", level: 0.7)
        PendingBakeJobStore.shared.enqueuePending(articleID: rows.merged, paragraphs: rows.mergedText, voiceID: "voiceA",
                                                  plan: .topDown(paragraphCount: 3))
        ListenResumePointStore.shared.save(article: rows.merged, paragraph: 1, at: date(2))
        var needed: [String: Data] = [:]
        needed["Alpha one."] = try bytes(env, rows.merged, paragraph: 0)
        needed["Gamma three."] = try bytes(env, rows.merged, paragraph: 2)
        needed["Beta changed."] = try bytes(env, rows.kept, paragraph: 1)
        return (rows, needed)
    }

    /// The migration's merge, with the app dying at each step of its audio work: a cold relaunch
    /// finds every paragraph's audio the kept page needs, under one key or the other, and finishes
    /// the merge, whether the merged page's directory is still there or already gone.
    func testAMergeStoppedAtAnyStepLosesNoAudioAndIsFinishedNextLaunch() throws {
        let count = try steps(of: { _ = try self.distinctDuplicateRows($0) }, { $0.migrateLegacy() })
        XCTAssertGreaterThan(count, 3)
        for k in 0..<count {
            let env = try LibraryTestEnvironment(fileBacked: true)
            defer { cleanUp(env) }
            let (rows, needed) = try distinctDuplicateRows(env)
            env.cache.faultHook = dieAt(k)
            XCTAssertTrue(env.library.migrateLegacy().saved, "step \(k)")
            XCTAssertEqual(pendingWork(env).count, 1, "step \(k): unfinished work is kept")

            try env.relaunch()
            try assertNothingLost(env, [rows.merged, rows.kept], needed, "died at step \(k)")
            XCTAssertEqual(env.library.finishAudioWork().finished, 1, "step \(k)")
            try assertMerged(rows, env, "step \(k):")
            for (i, text) in rows.keptText.enumerated() {
                XCTAssertEqual(try bytes(env, rows.kept, paragraph: i), needed[text], "step \(k): paragraph \(i)'s own audio")
            }
        }
    }

    /// Writes a stitched CAF like the queue does: chunk k's samples are all `level + k / 100`.
    private func writeStitched(_ env: LibraryTestEnvironment, _ key: UUID, _ index: Int, _ text: String,
                               lengths: [Int], level: Float) throws -> Data {
        var samples: [Float] = []
        for (k, n) in lengths.enumerated() { samples += [Float](repeating: level + Float(k) / 100, count: n) }
        let tmp = env.dir.appending(path: "stitch-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: tmp)
        let url = try env.cache.storeParagraph(articleID: key, paragraphIndex: index, sourceURL: tmp,
                                               duration: Double(samples.count) / 24_000, engineID: SpeechEngineID.kokoro.rawValue,
                                               voiceID: "kstub:af_heart", text: text,
                                               chunkDurations: lengths.count > 1 ? lengths.map { Double($0) / 24_000 } : nil)
        return try Data(contentsOf: url)
    }

    private struct LayoutFixture {
        let key: UUID
        let old: [String]
        let new: [String]
        let iAfter: Int
        let firstPiece: Int
        /// Text → bytes of the renderings that keep their text: the paragraph after the giant, the last.
        let kept: [String: Data]
        let giant: (text: String, bytes: Data)
    }

    /// A saved page on the pre-split blocks (public-domain chapter) with audio for its giant
    /// paragraph (stitched), the one after it and the last; the resume point and a pending render
    /// on the old numbering.
    private func layoutFixture(_ env: LibraryTestEnvironment) throws -> LayoutFixture {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false).paragraphs
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs
        let iGiant = old.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let key = UUID()
        let page = Page(key: key, title: title, byline: "example.com",
                        urlString: "https://example.com/classics/boscombe-valley", contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        try env.context.save()
        let plan = TextChunker.chunks(for: old[iGiant], limits: .kokoroCPU)
        let giant = try writeStitched(env, key, iGiant, old[iGiant], lengths: plan.indices.map { 2400 + 240 * $0 }, level: 0.1)
        var kept: [String: Data] = [:]
        kept[old[iGiant + 1]] = try writeStitched(env, key, iGiant + 1, old[iGiant + 1], lengths: [4800], level: 0.5)
        kept[old[old.count - 1]] = try writeStitched(env, key, old.count - 1, old[old.count - 1], lengths: [4800], level: 0.6)
        ListenResumePointStore.shared.save(article: key, paragraph: iGiant + 1, at: date(1))
        PendingBakeJobStore.shared.enqueuePending(articleID: key, paragraphs: old, voiceID: "voiceA",
                                                  plan: .topDown(paragraphCount: old.count))
        return LayoutFixture(key: key, old: old, new: new, iAfter: iGiant + 1, firstPiece: iGiant + 1, kept: kept,
                             giant: (old[iGiant], giant))
    }

    /// The layout pass, with the app dying at each step of its audio work: a cold relaunch finds
    /// every rendering (the giant paragraph's, or its slices) and finishes the work: unchanged
    /// paragraphs moved to their new index, the giant sliced, the resume point and the pending
    /// render on the new numbering.
    func testALayoutPassStoppedAtAnyStepLosesNoAudioAndIsFinishedNextLaunch() throws {
        let count = try steps(of: { _ = try self.layoutFixture($0) }, { $0.migrateParagraphLayout() })
        XCTAssertGreaterThan(count, 3)
        for k in 0..<count {
            let env = try LibraryTestEnvironment(fileBacked: true)
            defer { cleanUp(env) }
            let f = try layoutFixture(env)
            env.cache.faultHook = dieAt(k)
            env.library.migrateParagraphLayout()
            XCTAssertEqual(pendingWork(env).count, 1, "step \(k): unfinished work is kept")

            try env.relaunch()
            try assertNothingLost(env, [f.key], f.kept, "died at step \(k)")
            let cold = ArticleAudioCache(root: env.cache.root)
            let hashes = Set((cold.index(for: f.key)?.paragraphs ?? []).compactMap(\.textHash))
            XCTAssertTrue(hashes.contains(ArticleIdentity.paragraphHash(f.giant.text))
                          || hashes.contains(ArticleIdentity.paragraphHash(f.new[f.firstPiece])),
                          "died at step \(k): the giant's audio, or its first slice")

            XCTAssertEqual(env.library.finishAudioWork().finished, 1, "step \(k)")
            XCTAssertTrue(env.cache.isAligned(articleID: f.key, paragraphs: f.new), "step \(k)")
            let after = try XCTUnwrap(f.new.firstIndex(of: f.old[f.iAfter]))
            XCTAssertEqual(try bytes(env, f.key, paragraph: after), f.kept[f.old[f.iAfter]],
                           "step \(k): the paragraph after the giant moved with its audio")
            XCTAssertEqual(try bytes(env, f.key, paragraph: f.new.count - 1), f.kept[f.old[f.old.count - 1]], "step \(k)")
            XCTAssertEqual(env.cache.entry(articleID: f.key, paragraphIndex: f.firstPiece)?.textHash,
                           ArticleIdentity.paragraphHash(f.new[f.firstPiece]), "step \(k): the first piece is sliced")
            XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, after, "step \(k): the resume point follows")
            XCTAssertEqual(PendingBakeJobStore.shared.pendingJobs().first { $0.articleID == f.key }?.paragraphs, f.new, "step \(k)")
            XCTAssertTrue(pendingWork(env).isEmpty, "step \(k)")
        }
    }

    /// Work whose audio change fails isn't retired: it waits, with nothing lost, for a launch
    /// where it can finish.
    func testWorkThatFailsIsKeptUntilALaunchCanFinishIt() throws {
        let (rows, needed) = try distinctDuplicateRows(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: rows.merged) }
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertTrue(library.migrateLegacy().saved)
        XCTAssertEqual(pendingWork().count, 1, "not retired")

        try env.relaunch()
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertEqual(library.finishAudioWork().finished, 0, "still failing")
        XCTAssertEqual(pendingWork().count, 1, "still kept")
        try assertNothingLost(env, [rows.merged, rows.kept], needed, "while it fails")

        try env.relaunch()
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        try assertMerged(rows)
    }

    /// Two links for one address, neither holding text; the merged one still has audio from
    /// when it was played. The merge moves its directory whole; the app dies right after the
    /// rename. The next launch finds the audio under the kept key and retires the work.
    func testAMergeStoppedRightAfterMovingTheDirectoryIsFinishedNextLaunch() throws {
        let canonical = "https://example.com/link"
        let kept = Page(key: UUID(), title: "Link", byline: "example.com", urlString: canonical, contentState: .link, addedAt: date(0))
        let merged = Page(key: UUID(), title: "Link", byline: "example.com", urlString: canonical + "?utm_source=feed",
                          contentState: .link, addedAt: date(1))
        for page in [kept, merged] {
            page.canonicalURL = canonical
            env.context.insert(page)
        }
        try env.context.save()
        let keptKey = try XCTUnwrap(kept.key), mergedKey = try XCTUnwrap(merged.key)
        try env.storeAudio(mergedKey, paragraph: 0, text: "Played once.", level: 0.3)
        let audio = try XCTUnwrap(bytes(env, mergedKey, paragraph: 0))

        var steps: [ArticleAudioCache.ChangeStep] = []
        env.cache.faultHook = { steps.append($0); throw Died() }
        XCTAssertEqual(library.dedupe().mergedPages, 1)
        XCTAssertEqual(steps, [.movedDirectory], "died right after the rename")
        XCTAssertEqual(pendingWork().count, 1)

        try env.relaunch()
        try assertNothingLost(env, [keptKey], ["Played once.": audio], "after the rename")
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        XCTAssertFalse(env.cache.hasDirectory(for: mergedKey))
        XCTAssertEqual(try bytes(env, keptKey, paragraph: 0), audio)
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// The copy's save fails after dedupe merged two copies: the audio, the pending render and
    /// the crash-resume point are as they were, and the next launch merges them properly.
    func testAFailedSaveLeavesAudioPendingRendersAndTheResumePointAlone() throws {
        let rows = try duplicateRows()
        let audioBefore = (try audioFiles(rows.merged), try audioFiles(rows.kept))
        let jobsBefore = PendingBakeJobStore.shared.pendingJobs()
        let resumeBefore = ListenResumePointStore.shared.load()
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertFalse(library.migrateLegacy().saved)
        XCTAssertEqual(try audioFiles(rows.merged), audioBefore.0, "the merged copy's audio is untouched")
        XCTAssertEqual(try audioFiles(rows.kept), audioBefore.1, "and so is the kept one's")
        XCTAssertEqual(PendingBakeJobStore.shared.pendingJobs(), jobsBefore, "the pending render is still there")
        XCTAssertEqual(ListenResumePointStore.shared.load(), resumeBefore, "the resume point is unchanged")

        try env.relaunch()
        XCTAssertTrue(library.migrateLegacy().saved)
        try assertMerged(rows)
    }

    // MARK: Deleting

    /// A saved page in a folder, with audio and a pending render.
    private func pageWithAudio(_ path: String, in folder: Folder?) throws -> (Page, UUID) {
        let page = library.save(env.article("https://example.com/\(path)"), placement: .folder(folder))
        let key = try XCTUnwrap(page.key)
        try env.storeAudio(key, paragraphs: page.cachedListenParagraphs ?? [])
        PendingBakeJobStore.shared.enqueuePending(articleID: key, paragraphs: page.cachedListenParagraphs ?? [],
                                                  voiceID: "voiceA", plan: .topDown(paragraphCount: 2))
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: key) }
        return (page, key)
    }

    /// Deleting a page, or a folder with its contents, whose save fails: the pages, the folder
    /// and their audio and pending renders are all still there, and nothing waits to delete
    /// them later. Once a save works, the delete takes the audio with it.
    func testAFailedDeleteSaveKeepsThePagesAndTheirAudio() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let (loose, looseKey) = try pageWithAudio("loose", in: nil)
        let (_, shelvedKey) = try pageWithAudio("shelved", in: shelf)
        let audioBefore = (try audioFiles(looseKey), try audioFiles(shelvedKey))
        XCTAssertFalse(audioBefore.0.isEmpty)
        library.saveContext = { _ in throw SaveFailed() }

        library.delete(loose)
        try library.deleteFolder(shelf, keepContents: false)
        XCTAssertNotNil(library.page(key: looseKey), "the page is back")
        XCTAssertNotNil(library.page(key: shelvedKey))
        XCTAssertNotNil(library.folder(id: shelf.id), "and the folder")
        XCTAssertEqual(try audioFiles(looseKey), audioBefore.0, "its audio is untouched")
        XCTAssertEqual(try audioFiles(shelvedKey), audioBefore.1)
        XCTAssertEqual(Set(PendingBakeJobStore.shared.pendingJobs().map(\.articleID)).intersection([looseKey, shelvedKey]),
                       [looseKey, shelvedKey], "the pending renders stay")
        XCTAssertTrue(pendingWork().isEmpty, "nothing waits to delete the audio later")

        try env.relaunch()
        XCTAssertNotNil(library.page(key: looseKey), "nothing was saved")
        XCTAssertEqual(try audioFiles(looseKey), audioBefore.0)

        library.delete(try XCTUnwrap(library.page(key: looseKey)))
        XCTAssertNil(library.page(key: looseKey))
        XCTAssertFalse(env.cache.hasDirectory(for: looseKey), "a saved delete takes its audio")
        XCTAssertFalse(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == looseKey })
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// The app dies right after a delete's save, before its audio went: the next launch deletes
    /// it.
    func testADeleteSavedButNotFinishedTakesItsAudioNextLaunch() throws {
        let (page, key) = try pageWithAudio("doomed", in: nil)
        library.saveContext = { try $0.save(); throw SaveFailed() }
        library.delete(page)
        XCTAssertTrue(env.cache.hasDirectory(for: key), "the audio work hadn't run")

        try env.relaunch()
        XCTAssertNil(library.page(key: key), "the delete was saved")
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        XCTAssertFalse(env.cache.hasDirectory(for: key))
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// The app dies right after the copy's save, before the audio work: the next launch finds
    /// the work in the store and does it.
    func testWorkLeftByALaunchThatDiedAfterItsSaveIsDoneNextLaunch() throws {
        let rows = try duplicateRows()
        let audioBefore = try audioFiles(rows.merged)
        // Saved, then gone before anything else ran.
        library.saveContext = { try $0.save(); throw SaveFailed() }
        library.migrateLegacy()
        XCTAssertEqual(try audioFiles(rows.merged), audioBefore, "the work hadn't run")

        try env.relaunch()
        XCTAssertEqual(env.pages().map(\.key), [rows.kept], "the merge itself was saved")
        XCTAssertEqual(pendingWork().count, 1, "with its audio work")
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        try assertMerged(rows)
        XCTAssertEqual(library.migrateLegacy().copiedArticles, 0, "the copy was recorded")
    }

    /// The work ran but its records weren't deleted (the app died before that save): doing it
    /// again changes nothing, and the crash-resume point isn't moved a second time.
    func testWorkDoneTwiceMovesNothingTwice() throws {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title)
        let iGiant = old.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let iAfter = iGiant + 1
        let key = UUID()
        let page = Page(key: key, title: title, byline: "example.com",
                        urlString: "https://example.com/classics/boscombe-valley", contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old.paragraphs)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        try env.context.save()
        try env.storeAudio(key, paragraph: iAfter, text: old.paragraphs[iAfter])
        ListenResumePointStore.shared.save(article: key, paragraph: iAfter, at: date(1))

        var saves = 0
        library.saveContext = { context in
            saves += 1
            if saves == 2 { throw SaveFailed() } // the save that deletes the done work
            try context.save()
        }
        library.migrateParagraphLayout()
        let shifted = iAfter + 3
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, shifted)
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: shifted)?.textHash,
                       ArticleIdentity.paragraphHash(new.paragraphs[shifted]))
        let files = try audioFiles(key).keys.sorted()

        try env.relaunch()
        XCTAssertEqual(pendingWork().count, 1, "the done work's record survived")
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, shifted, "moved once")
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: shifted)?.textHash,
                       ArticleIdentity.paragraphHash(new.paragraphs[shifted]))
        XCTAssertEqual(try audioFiles(key).keys.sorted(), files, "the audio is as the first run left it")
        XCTAssertTrue(pendingWork().isEmpty)
    }

    // MARK: Work checked against the committed page

    /// The page at `url` opened with newer text, as the reader does (`readerArticle`).
    private func refresh(_ url: String, title: String, to paragraphs: [String]) {
        let extracted = ExtractedArticle(title: title, siteName: nil, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        _ = library.readerArticle(url: URL(string: url)!, extracted: extracted)
    }

    private let boscombeURL = "https://example.com/classics/boscombe-valley"
    private let boscombeTitle = "The Boscombe Valley Mystery"

    /// The launch's layout pass can't save. It is rolled back with its planned audio work: the
    /// page is opened with newer text and that is rendered while saves still fail, and the save
    /// that finally succeeds stores the newer page without aligning its audio to the old plan.
    func testAFailedLayoutSaveIsRolledBackSoALaterSaveCantRunItOnNewerText() throws {
        let f = try layoutFixture(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: f.key) }
        var failing = true
        library.saveContext = { context in
            if failing { throw SaveFailed() }
            try context.save()
        }
        XCTAssertTrue(library.migrateParagraphLayout().rolledBack)
        XCTAssertTrue(pendingWork().isEmpty, "no audio work left planned")
        XCTAssertEqual(library.page(key: f.key)?.listenBlocksVersion, 2, "the page is as it was")

        let fresh = ["A newer first paragraph.", "A newer second paragraph."]
        refresh(boscombeURL, title: boscombeTitle, to: fresh)
        var rendered: [Data] = []
        for (i, text) in fresh.enumerated() {
            try env.storeAudio(f.key, paragraph: i, text: text, level: 0.3 + Float(i) / 10)
            rendered.append(try XCTUnwrap(bytes(env, f.key, paragraph: i)))
        }

        failing = false
        XCTAssertTrue(library.commit("later"))
        XCTAssertEqual(library.page(key: f.key)?.cachedListenParagraphs, fresh)
        for (i, text) in fresh.enumerated() {
            XCTAssertEqual(env.cache.entry(articleID: f.key, paragraphIndex: i)?.textHash, ArticleIdentity.paragraphHash(text))
            XCTAssertEqual(try bytes(env, f.key, paragraph: i), rendered[i], "the newer text's audio is all there")
        }
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// A layout pass whose save failed is planned again by the next launch.
    func testAFailedLayoutSaveIsPlannedAgainNextLaunch() throws {
        let f = try layoutFixture(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: f.key) }
        library.saveContext = { _ in throw SaveFailed() }
        XCTAssertTrue(library.migrateParagraphLayout().rolledBack)

        try env.relaunch()
        let report = library.migrateParagraphLayout()
        XCTAssertEqual(report.articles, 1)
        XCTAssertFalse(report.rolledBack)
        XCTAssertTrue(env.cache.isAligned(articleID: f.key, paragraphs: f.new))
        XCTAssertEqual(env.cache.entry(articleID: f.key, paragraphIndex: f.firstPiece)?.textHash,
                       ArticleIdentity.paragraphHash(f.new[f.firstPiece]))
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// Layout work that couldn't finish waits; meanwhile the page is opened with newer text, which
    /// is rendered. Next launch the work no longer matches the page and is dropped, leaving the
    /// newer audio alone.
    func testWaitingLayoutWorkWhosePageChangedSinceIsDropped() throws {
        let f = try layoutFixture(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: f.key) }
        env.cache.faultHook = { _ in throw Died() }
        library.migrateParagraphLayout()
        XCTAssertEqual(pendingWork().count, 1, "waiting")
        env.cache.faultHook = nil

        let fresh = ["A newer first paragraph.", "A newer second paragraph."]
        refresh(boscombeURL, title: boscombeTitle, to: fresh)
        XCTAssertEqual(library.page(key: f.key)?.cachedListenParagraphs, fresh)
        var rendered: [Data] = []
        for (i, text) in fresh.enumerated() {
            try env.storeAudio(f.key, paragraph: i, text: text, level: 0.3 + Float(i) / 10)
            rendered.append(try XCTUnwrap(bytes(env, f.key, paragraph: i)))
        }

        try env.relaunch()
        XCTAssertEqual(library.finishAudioWork().finished, 1, "retired")
        for (i, text) in fresh.enumerated() {
            XCTAssertEqual(env.cache.entry(articleID: f.key, paragraphIndex: i)?.textHash, ArticleIdentity.paragraphHash(text))
            XCTAssertEqual(try bytes(env, f.key, paragraph: i), rendered[i], "the newer text's audio is untouched")
        }
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// A merge that couldn't finish waits; meanwhile the kept page is opened with newer text and
    /// its changed paragraph rendered. Next launch the merged audio fills what the kept page holds
    /// now, and the newer audio stays.
    func testAWaitingMergeFollowsWhatTheKeptPageHoldsNow() throws {
        let (rows, needed) = try distinctDuplicateRows(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: rows.merged) }
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertTrue(library.migrateLegacy().saved)
        XCTAssertEqual(pendingWork().count, 1, "waiting")
        env.cache.faultHook = nil

        let fresh = ["Alpha one.", "Beta edited again.", "Gamma three."]
        refresh("https://example.com/dup", title: "Legacy", to: fresh)
        XCTAssertEqual(library.page(key: rows.kept)?.cachedListenParagraphs, fresh)
        try env.storeAudio(rows.kept, paragraph: 1, text: "Beta edited again.", level: 0.9)
        let edited = try XCTUnwrap(bytes(env, rows.kept, paragraph: 1))

        try env.relaunch()
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        XCTAssertEqual(try bytes(env, rows.kept, paragraph: 0), needed["Alpha one."], "the merged page's audio fills in")
        XCTAssertEqual(try bytes(env, rows.kept, paragraph: 1), edited, "the newer audio stays")
        XCTAssertEqual(try bytes(env, rows.kept, paragraph: 2), needed["Gamma three."])
        XCTAssertFalse(env.cache.hasDirectory(for: rows.merged))
        XCTAssertTrue(pendingWork().isEmpty)
    }

    /// A merge that couldn't finish waits, with the crash-resume point on the merged page's
    /// "Alpha one."; meanwhile the kept page's paragraphs are reordered. Next launch the resume
    /// point, and the crash target read at launch, land where the kept page holds "Alpha one."
    /// now: on the same paragraphs its audio is aligned with, not the ones planned.
    func testAWaitingMergeMovesTheResumePointOntoWhatTheKeptPageHoldsNow() throws {
        let (rows, _) = try distinctDuplicateRows(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: rows.merged) }
        ListenResumePointStore.shared.save(article: rows.merged, paragraph: 0, at: date(2))
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertTrue(library.migrateLegacy().saved)
        XCTAssertEqual(pendingWork().count, 1, "waiting")
        env.cache.faultHook = nil

        let reordered = ["Gamma three.", "Alpha one.", "Beta changed."]
        refresh("https://example.com/dup", title: "Legacy", to: reordered)
        XCTAssertEqual(library.page(key: rows.kept)?.cachedListenParagraphs, reordered)

        try env.relaunch()
        env.tts.pendingResume = ListenResumeTarget(articleKey: rows.merged.uuidString, paragraph: 0, at: date(2))
        XCTAssertEqual(library.finishAudioWork().finished, 1)
        XCTAssertEqual(env.cache.entry(articleID: rows.kept, paragraphIndex: 1)?.textHash,
                       ArticleIdentity.paragraphHash("Alpha one."), "the audio follows what the kept page holds")
        let resume = try XCTUnwrap(ListenResumePointStore.shared.load())
        XCTAssertEqual(resume.articleKey, rows.kept.uuidString)
        XCTAssertEqual(resume.paragraph, 1, "the resume point is on \"Alpha one.\" too")
        XCTAssertEqual(env.tts.pendingResume.map { $0.matches(rows.kept) }, true)
        XCTAssertEqual(env.tts.pendingResume?.paragraph, 1, "and so is the crash target")
    }

    /// A merge that couldn't finish waits; meanwhile the kept page is deleted. The delete's save
    /// does the waiting merge first, then the delete's own audio work: no page holds the merged
    /// audio, so it is left to the cache's age prune, not moved under a deleted key.
    func testAWaitingMergeWhoseKeptPageIsDeletedLeavesItsAudioToTheAgePrune() throws {
        let (rows, _) = try distinctDuplicateRows(env)
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: rows.merged) }
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertTrue(library.migrateLegacy().saved)
        env.cache.faultHook = nil
        library.delete(try XCTUnwrap(library.page(key: rows.kept)))
        XCTAssertTrue(pendingWork().isEmpty, "the waiting merge, then the delete, both done after its save")

        try env.relaunch()
        XCTAssertEqual(library.finishAudioWork().finished, 0)
        XCTAssertTrue(env.cache.hasCache(for: rows.merged), "not deleted outright")
        XCTAssertEqual(env.cache.loadMeta(for: rows.merged)?.kind, .ephemeral)
        XCTAssertFalse(env.cache.hasDirectory(for: rows.kept), "nothing moved under the deleted page's key")
        XCTAssertFalse(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == rows.merged })
        XCTAssertTrue(pendingWork().isEmpty)
    }
}
