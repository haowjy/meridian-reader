import Foundation
import SwiftData

/// Saved-article lookups and writes that enforce **one SavedArticle per canonical URL**.
/// Browse and Saved both go through here so identity resolution is identical.
@MainActor
enum ArticleLibrary {
    // MARK: - Lookup

    static func savedArticle(canonicalURL: String, in context: ModelContext) -> SavedArticle? {
        var descriptor = FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.canonicalURL == canonicalURL },
            sortBy: [SortDescriptor(\.savedAt)]
        )
        descriptor.fetchLimit = 1
        if let hit = try? context.fetch(descriptor).first { return hit }
        // Rows saved before v2 have no canonicalURL until `migrate` runs.
        let legacy = FetchDescriptor<SavedArticle>(predicate: #Predicate { $0.canonicalURL == "" })
        return (try? context.fetch(legacy))?.first {
            ArticleIdentity.canonicalURLString(from: $0.urlString) == canonicalURL
        }
    }

    static func savedArticle(id: UUID, in context: ModelContext) -> SavedArticle? {
        var descriptor = FetchDescriptor<SavedArticle>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Open (Browse)

    /// Resolve a fresh extraction to its article identity:
    /// saved row for the canonical URL → its id / playhead / bookmark.fill; otherwise the
    /// URL-derived key. If the saved copy's listen text changed, the saved row is refreshed
    /// (newest content wins) and per-paragraph audio is reconciled on open.
    static func readerArticle(url: URL, extracted: ExtractedArticle, in context: ModelContext) -> ReaderArticle {
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let existing = savedArticle(canonicalURL: canonical, in: context)
        let key = existing?.id ?? ArticleIdentity.articleKey(canonicalURL: canonical)
        var article = ReaderArticle(id: key, url: url, extracted: extracted)
        let freshFP = ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs)

        if let existing {
            let stored = existing.cachedListenParagraphs
            article.trustedParagraphs = stored
            article.resumeParagraph = existing.playbackParagraphIndex
            article.faviconData = existing.faviconData
            let storedFP = stored.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if storedFP != freshFP {
                update(existing, from: article)
                try? context.save()
            }
            log("open \(canonical) key=\(short(key)) saved fp=\(freshFP.prefix(8)) storedFp=\(storedFP?.prefix(8) ?? "nil") \(storedFP == freshFP ? "same" : "CHANGED→refreshed")")
        } else {
            log("open \(canonical) key=\(short(key)) unsaved fp=\(freshFP.prefix(8)) v1key=\(article.legacyCacheKeys.first.map(short) ?? "-")")
        }
        return article
    }

    // MARK: - Save / Unsave

    /// Idempotent: returns the existing row for the canonical URL (content refreshed if the
    /// listen text changed) or inserts one whose id is the reader key.
    @discardableResult
    static func save(_ article: ReaderArticle, playhead: Int? = nil, in context: ModelContext) -> SavedArticle {
        let row: SavedArticle
        if let existing = savedArticle(canonicalURL: article.canonicalURL, in: context)
            ?? savedArticle(id: article.id, in: context) {
            let storedFP = existing.cachedListenParagraphs.map { ArticleIdentity.contentFingerprint(paragraphs: $0) }
            if storedFP != ArticleIdentity.contentFingerprint(paragraphs: article.document.paragraphs) {
                update(existing, from: article)
            }
            if existing.faviconData == nil { existing.faviconData = article.faviconData }
            row = existing
            log("save dedupe \(article.canonicalURL) → existing \(short(existing.id))")
        } else {
            let words = article.plainText.split { $0.isWhitespace || $0.isNewline }.count
            row = SavedArticle(
                id: article.id,
                urlString: article.urlString,
                title: article.title,
                siteDomain: article.siteDomain,
                cleanedHTML: article.cleanedHTML,
                plainText: article.plainText,
                wordCount: words,
                estimatedMinutes: max(1, Int((Double(words) / 200.0).rounded(.up))),
                excerpt: article.excerpt,
                playbackParagraphIndex: playhead ?? article.resumeParagraph,
                faviconData: article.faviconData
            )
            if !article.document.isEmpty {
                row.storeListenParagraphs(article.document.paragraphs)
            } else {
                row.storeListenParagraphs(SavedArticle.buildListenDocument(
                    plainText: article.plainText,
                    cleanedHTML: article.cleanedHTML,
                    title: article.title
                ).paragraphs)
            }
            context.insert(row)
            log("save new \(article.canonicalURL) id=\(short(row.id))")
        }
        if let playhead { row.playbackParagraphIndex = playhead }
        try? context.save()
        return row
    }

    /// Remove every saved row for this article (id or canonical URL). Audio is NOT deleted here;
    /// the caller marks it ephemeral so the reader keeps playing and the TTL owns cleanup.
    static func unsave(id: UUID, canonicalURL: String, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.id == id || $0.canonicalURL == canonicalURL }
        ))) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
        log("unsave \(canonicalURL) removed=\(rows.count)")
    }

    private static func update(_ row: SavedArticle, from article: ReaderArticle) {
        let words = article.plainText.split { $0.isWhitespace || $0.isNewline }.count
        row.urlString = article.urlString
        row.canonicalURL = article.canonicalURL
        row.title = article.title
        row.cleanedHTML = article.cleanedHTML
        row.plainText = article.plainText
        row.excerpt = article.excerpt
        row.wordCount = words
        row.estimatedMinutes = max(1, Int((Double(words) / 200.0).rounded(.up)))
        if !article.document.isEmpty {
            row.storeListenParagraphs(article.document.paragraphs)
            row.playbackParagraphIndex = min(row.playbackParagraphIndex, max(0, article.document.count - 1))
        }
    }

    // MARK: - One-time backfill + duplicate merge (idempotent; runs at launch)

    /// Backfills `canonicalURL` and merges SavedArticles that share a canonical URL.
    /// Keeper = furthest listen progress, then oldest save. Audio from extras is merged into the
    /// keeper (per-paragraph hashes decide what is reusable); extras are deleted.
    static func migrate(in context: ModelContext, localTTS: LocalTTSCoordinator) {
        guard let rows = try? context.fetch(FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.savedAt)])) else { return }
        var backfilled = 0
        for row in rows {
            let canonical = ArticleIdentity.canonicalURLString(from: row.urlString)
            if row.canonicalURL != canonical {
                row.canonicalURL = canonical
                backfilled += 1
            }
        }
        let groups = Dictionary(grouping: rows, by: \.canonicalURL).filter { $0.value.count > 1 }
        var merged = 0
        let cache = localTTS.audioCache
        for (canonical, dupes) in groups {
            let keeper = dupes.max { a, b in
                if a.playbackParagraphIndex != b.playbackParagraphIndex {
                    return a.playbackParagraphIndex < b.playbackParagraphIndex
                }
                return a.savedAt > b.savedAt // older wins ties
            }!
            let keeperParagraphs = keeper.listenDocument().paragraphs
            cache.stampMissingHashes(articleID: keeper.id, paragraphs: keeperParagraphs)
            for extra in dupes where extra.id != keeper.id {
                cache.stampMissingHashes(articleID: extra.id, paragraphs: extra.listenDocument().paragraphs)
                if cache.hasCache(for: extra.id) {
                    try? cache.rekeyCache(from: extra.id, to: keeper.id)
                    localTTS.synthQueue.remove(cacheKey: extra.id)
                }
                if keeper.faviconData == nil { keeper.faviconData = extra.faviconData }
                log("merge duplicate \(canonical): \(short(extra.id)) → keeper \(short(keeper.id))")
                context.delete(extra)
                merged += 1
            }
            cache.reconcile(articleID: keeper.id, paragraphs: keeperParagraphs)
        }
        if backfilled > 0 || merged > 0 {
            try? context.save()
            localTTS.noteBakeMarksChanged()
        }
        log("migrate v2: rows=\(rows.count) backfilled=\(backfilled) mergedDuplicates=\(merged)")
    }

    // MARK: - Paragraph layout v3 (giant paragraphs split; runs once per row at launch)

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

    /// Paragraph layout v3 (2026-09-25): paragraphs over 1,200 characters are split at sentence
    /// ends (`ParagraphSplitter`). For every saved row still on older listen blocks: rebuild its
    /// paragraphs, move the reading position to the same sentence (character-offset mapping),
    /// align its cached audio (slice pieces whose chunks line up, move shifted paragraphs,
    /// re-render only the rest), and remap the crash-resume point and any pending bake job.
    /// Idempotent (rows are stamped with `ListenHTMLBlocks.version`). Logged per article
    /// (`paragraph_layout_migration`).
    @discardableResult
    static func migrateParagraphLayout(in context: ModelContext, localTTS: LocalTTSCoordinator) -> LayoutMigrationReport {
        var report = LayoutMigrationReport()
        guard let rows = try? context.fetch(FetchDescriptor<SavedArticle>(sortBy: [SortDescriptor(\.savedAt)])) else {
            return report
        }
        let stale = rows.filter { $0.listenBlocksVersion < ListenHTMLBlocks.version }
        guard !stale.isEmpty else { return report }
        let cache = localTTS.audioCache
        let resume = ListenResumePointStore.shared.load()
        let scheduler = BackgroundAudioBakeScheduler.shared
        for row in stale {
            let t0 = ListenTimingLog.now()
            // The list the stored position / audio refer to: the stored v2 blocks when present,
            // else what the pre-split rules produce from the saved HTML.
            let storedOld = row.listenBlocksVersion == 2 ? SavedArticle.decodeAnyListenParagraphs(row.listenBlocksData) : nil
            let old = storedOld.map { ParagraphDocument(parts: $0) }
                ?? ParagraphDocument.forListening(plainText: row.plainText, cleanedHTML: row.cleanedHTML,
                                                  matchingTitle: row.title, splitLong: false)
            let new = SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML, title: row.title)
            let before = ParagraphPositionMap.Position(paragraph: row.playbackParagraphIndex, utf16Offset: row.playbackUTF16Offset)
            let after = ParagraphPositionMap.map(paragraph: before.paragraph, utf16Offset: before.utf16Offset, from: old, to: new)
            row.storeListenParagraphs(new.paragraphs)
            row.playbackParagraphIndex = after.paragraph
            row.playbackUTF16Offset = after.utf16Offset

            var split = ArticleAudioCache.SplitRemapResult()
            var rec = ArticleAudioCache.ReconcileResult()
            if cache.hasCache(for: row.id) {
                cache.stampMissingHashes(articleID: row.id, paragraphs: old.paragraphs)
                split = cache.remapSplitParagraphs(articleID: row.id, paragraphs: new.paragraphs) {
                    localTTS.chunkPlan(engineID: $0, text: $1)
                }
                rec = cache.reconcile(articleID: row.id, paragraphs: new.paragraphs)
            }
            if let r = resume, r.articleKey == row.id.uuidString {
                ListenResumePointStore.shared.save(article: row.id,
                                                   paragraph: ParagraphPositionMap.mapParagraphStart(r.paragraph, from: old, to: new),
                                                   at: r.at)
            }
            localTTS.remapPendingResume(article: row.id) {
                ParagraphPositionMap.mapParagraphStart($0, from: old, to: new)
            }
            if let job = scheduler.pendingJobs().first(where: { $0.articleID == row.id }) {
                let start = ParagraphPositionMap.mapParagraphStart(job.priorityStart, from: ParagraphDocument(parts: job.paragraphs), to: new)
                scheduler.enqueuePending(articleID: row.id, paragraphs: new.paragraphs, rate: job.rate, voiceID: job.voiceID,
                                         plan: BakePriorityPlan(priorityStart: start,
                                                                fillGapsFromTopAfterPriority: job.fillGapsFromTopAfterPriority,
                                                                paragraphCount: new.count))
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
                "key": ListenTimingLog.shortKey(row.id), "old_paragraphs": old.count, "new_paragraphs": new.count,
                "split": splitCount, "from_stored": storedOld != nil,
                "pos_old": "\(before.paragraph)@\(before.utf16Offset)", "pos_new": "\(after.paragraph)@\(after.utf16Offset)",
                "audio_kept": rec.kept, "audio_moved": rec.remapped, "audio_dropped": rec.dropped,
                "audio_sliced": split.sliced, "audio_misaligned": split.misaligned, "ms": ListenTimingLog.ms(since: t0),
            ])
            log("layout v3 \(short(row.id)): paragraphs \(old.count)→\(new.count) (split \(splitCount)), position \(before.paragraph)→\(after.paragraph), audio kept \(rec.kept) moved \(rec.remapped) sliced \(split.sliced) dropped \(rec.dropped)")
        }
        try? context.save()
        localTTS.noteBakeMarksChanged()
        return report
    }

    // MARK: - Logging

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    private static func log(_ message: String) {
        print("[ArticleLibrary] \(message)")
        ListenDebugLog.shared.append("lib: \(message)")
    }
}
