import Foundation
import SwiftData

/// Launch maintenance on the library (`migrateLegacy` and `dedupe` live in their own files), the
/// trim of finished chapters' audio, "audio ready", and crash-resume lookup.
extension LibraryStore {
    // MARK: - Paragraph layout

    struct LayoutMigrationReport: Equatable {
        var articles = 0
        var oldParagraphs = 0
        var newParagraphs = 0
        var splitParagraphs = 0
        var audioSliced = 0
        var audioMisaligned = 0
        var audioMoved = 0
        var audioDropped = 0
    }

    /// Paragraph layout v3 (paragraphs over 1,200 characters split at sentence ends, see
    /// `ParagraphSplitter`) and any later `ListenHTMLBlocks.version`: for every page holding text
    /// on older listen blocks, rebuild its paragraphs, move its position to the same sentence,
    /// align its cached audio (slice pieces whose chunks line up, move shifted paragraphs,
    /// re-render only the rest), and remap the crash-resume point and any pending bake job.
    /// Idempotent: pages are stamped with the version. Logged per page
    /// (`paragraph_layout_migration`).
    @discardableResult
    func migrateParagraphLayout() -> LayoutMigrationReport {
        var report = LayoutMigrationReport()
        let version = ListenHTMLBlocks.version
        let stale = ((try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.listenBlocksVersion < version }))) ?? [])
            .filter(\.hasText)
        guard !stale.isEmpty else { return report }
        let cache = tts.audioCache
        let resume = ListenResumePointStore.shared.load()
        let pendingStore = PendingBakeJobStore.shared
        for page in stale {
            let t0 = ListenTimingLog.now()
            // The list the stored position and audio refer to: the stored v2 blocks when present,
            // else what the pre-split rules produce from the saved HTML.
            let storedOld = page.listenBlocksVersion == 2 ? Page.decodeAnyListenParagraphs(page.listenBlocksData) : nil
            let old = storedOld.map { ParagraphDocument(parts: $0) }
                ?? ParagraphDocument.forListening(plainText: page.plainText, cleanedHTML: page.cleanedHTML,
                                                  matchingTitle: page.title, splitLong: false)
            let new = Page.buildListenDocument(plainText: page.plainText, cleanedHTML: page.cleanedHTML, title: page.title)
            let before = ParagraphPositionMap.Position(paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
            let after = ParagraphPositionMap.map(paragraph: before.paragraph, utf16Offset: before.utf16Offset, from: old, to: new)
            page.storeListenParagraphs(new.paragraphs)
            page.positionParagraph = after.paragraph
            page.positionUTF16 = after.utf16Offset

            var split = ArticleAudioCache.SplitRemapResult()
            var rec = ArticleAudioCache.ReconcileResult()
            if let key = page.key {
                if cache.hasCache(for: key) {
                    cache.stampMissingHashes(articleID: key, paragraphs: old.paragraphs)
                    split = cache.remapSplitParagraphs(articleID: key, paragraphs: new.paragraphs) {
                        self.tts.chunkPlan(engineID: $0, text: $1)
                    }
                    rec = cache.reconcile(articleID: key, paragraphs: new.paragraphs)
                }
                if let r = resume, r.articleKey == key.uuidString {
                    ListenResumePointStore.shared.save(article: key,
                                                       paragraph: ParagraphPositionMap.mapParagraphStart(r.paragraph, from: old, to: new),
                                                       at: r.at)
                }
                tts.remapPendingResume(article: key) { ParagraphPositionMap.mapParagraphStart($0, from: old, to: new) }
                if let job = pendingStore.pendingJobs().first(where: { $0.articleID == key }) {
                    let start = ParagraphPositionMap.mapParagraphStart(job.priorityStart,
                                                                       from: ParagraphDocument(parts: job.paragraphs), to: new)
                    pendingStore.enqueuePending(articleID: key, paragraphs: new.paragraphs, voiceID: job.voiceID,
                                                plan: BakePriorityPlan(priorityStart: start,
                                                                       fillGapsFromTopAfterPriority: job.fillGapsFromTopAfterPriority,
                                                                       paragraphCount: new.count))
                }
            }
            let splitCount = old.paragraphs.filter { ParagraphSplitter.pieces($0).count > 1 }.count
            report.articles += 1
            report.oldParagraphs += old.count
            report.newParagraphs += new.count
            report.splitParagraphs += splitCount
            report.audioSliced += split.sliced
            report.audioMisaligned += split.misaligned
            report.audioMoved += rec.remapped
            report.audioDropped += rec.dropped
            ListenTimingLog.log("paragraph_layout_migration", [
                "key": page.key.map(ListenTimingLog.shortKey) ?? "-", "old_paragraphs": old.count,
                "new_paragraphs": new.count, "split": splitCount, "from_stored": storedOld != nil,
                "pos_old": "\(before.paragraph)@\(before.utf16Offset)", "pos_new": "\(after.paragraph)@\(after.utf16Offset)",
                "audio_kept": rec.kept, "audio_moved": rec.remapped, "audio_dropped": rec.dropped,
                "audio_sliced": split.sliced, "audio_misaligned": split.misaligned, "ms": ListenTimingLog.ms(since: t0),
            ])
            log("layout v\(version) \(Self.short(page.key)): paragraphs \(old.count)→\(new.count) (split \(splitCount)), position \(before.paragraph)→\(after.paragraph), audio kept \(rec.kept) moved \(rec.remapped) sliced \(split.sliced) dropped \(rec.dropped)")
        }
        commit("layout migration")
        tts.noteBakeMarksChanged()
        return report
    }

    // MARK: - Prune

    struct PruneReport: Equatable {
        var deletedPages = 0
        var clearedLinkCaches = 0
    }

    /// Pages not in the Library and not played for 7 days are deleted, except the page played
    /// most recently (what the Now Playing bar restores). Their audio is already ephemeral; the
    /// audio cache's own age and size prune removes it. Link pages' text caches unplayed for 7
    /// days are cleared; the links stay.
    @discardableResult
    func pruneUnsaved() -> PruneReport {
        var report = PruneReport()
        let cutoff = now().addingTimeInterval(-Self.unsavedKeepInterval)
        var latest = FetchDescriptor<Page>(sortBy: [SortDescriptor(\Page.lastPlayedAt, order: .reverse)])
        latest.fetchLimit = 1
        let lastPlayed = (try? context.fetch(latest))?.first.flatMap { $0.lastPlayedAt == nil ? nil : $0 }
        for page in (try? context.fetch(LibraryQueries.prunable(before: cutoff))) ?? [] where page !== lastPlayed {
            log("prune \(Self.short(page.key)) (not in Library, last played \(page.lastPlayedAt.map { "\($0)" } ?? "never"))")
            context.delete(page)
            report.deletedPages += 1
        }
        for page in (try? context.fetch(LibraryQueries.staleLinkCaches(before: cutoff))) ?? [] where page !== lastPlayed {
            clearText(page)
            page.lastPlayedAt = nil
            report.clearedLinkCaches += 1
        }
        if report != PruneReport() { commit("prune") }
        return report
    }

    // MARK: - Finished chapters' audio (D7)

    /// Deletes the audio of finished chapters more than 2 behind the book's or series' place;
    /// the text stays. A direct delete, not ephemeral marking, so the unsaved-audio size cap is
    /// unaffected. Returns how many chapters lost their audio.
    @discardableResult
    func trimFinishedAudio(folder: Folder) -> Int {
        guard folder.kind.isFixed, let place = folder.currentPageKey else { return 0 }
        let order = playOrder(of: folder)
        guard let current = order.firstIndex(where: { $0.key == place }), current > 2 else { return 0 }
        var trimmed = 0
        for page in order[..<(current - 2)] where page.finishedAt != nil {
            guard let key = page.key, tts.audioCache.hasCache(for: key) else { continue }
            try? tts.clearListenAudio(for: key)
            trimmed += 1
        }
        if trimmed > 0 { log("trimmed audio of \(trimmed) finished chapters in \(folder.name)") }
        return trimmed
    }

    // MARK: - Audio ready

    /// Every listen paragraph of the page has audio rendered in this voice (the cache voice id,
    /// as `SpeechController.cacheVoiceID` gives it). Apple voices render nothing ahead, so a page
    /// is never "ready" for them, which is right: they need no file.
    func isAudioReady(_ page: Page, voiceID: String) -> Bool {
        guard let key = page.key else { return false }
        return tts.audioCache.isAudioReady(articleID: key, paragraphCount: page.paragraphCount,
                                           engineID: tts.cacheEngineID, voiceID: tts.normalizedCacheVoice(voiceID))
    }

    // MARK: - Crash resume

    /// The page a crash-resume target names: its full key, or the 8-character prefix older crash
    /// markers wrote.
    func page(matching target: ListenResumeTarget) -> Page? {
        if let key = UUID(uuidString: target.articleKey) { return page(key: key) }
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        return pages.first { $0.key.map(target.matches) == true }
    }
}
