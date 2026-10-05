import Foundation
import SwiftData

/// The audio work planned since the last save: `LibraryAudioWork` records inserted with the
/// library change, and the crash-resume point as that work will leave it.
struct LibraryAudioWorkPlan {
    var work: [LibraryAudioWork] = []
    var nextSequence = 0
    /// Loaded with the first planned work, then moved along by each one, so a later step finds
    /// the point where an earlier one leaves it.
    var resume: ListenResumeTarget?
    var resumeLoaded = false
    /// Keys an `align` in this plan stamps (in the old numbering) before anything else moves.
    var aligned: Set<UUID> = []
}

/// A record whose postconditions don't hold after it ran.
enum LibraryAudioWorkError: Error {
    case notAligned(UUID)
}

/// Files outside the library store change only after the library change they belong to is saved.
/// The layout pass and dedupe plan their audio work (`planAlign`, `planMerge`) as records in the
/// same save; `commit` does it once the save succeeds; a launch that died in between finishes it
/// (`finishAudioWork`); a save that fails and is rolled back (`rollBack`) leaves every file alone.
extension LibraryStore {
    // MARK: - Planning

    /// `key`'s audio, pending render and crash-resume point follow its rebuilt paragraphs.
    func planAlign(key: UUID, old: [String], new: [String]) {
        let work = LibraryAudioWork(sequence: nextAudioWorkSequence(), kind: .align, key: key,
                                    paragraphs: new, sourceParagraphs: old)
        planResumePoint(work)
        audioPlan.aligned.insert(key)
        context.insert(work)
        audioPlan.work.append(work)
    }

    /// The merged page's audio moves under the kept page's key (per-paragraph hashes decide what
    /// is reusable), its pending render is dropped, and the crash-resume point follows.
    func planMerge(from: UUID, into to: UUID, fromParagraphs: [String], paragraphs: [String]) {
        let work = LibraryAudioWork(sequence: nextAudioWorkSequence(), kind: .merge, key: to, fromKey: from,
                                    paragraphs: paragraphs, sourceParagraphs: fromParagraphs)
        work.stampsSource = !audioPlan.aligned.contains(from)
        work.stampsTarget = !audioPlan.aligned.contains(to)
        planResumePoint(work)
        context.insert(work)
        audioPlan.work.append(work)
    }

    /// After a failed save: the context's changes and the work planned with them are dropped.
    func rollBack() {
        context.rollback()
        audioPlan = LibraryAudioWorkPlan()
    }

    private func nextAudioWorkSequence() -> Int {
        if audioPlan.work.isEmpty {
            var last = FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
            last.fetchLimit = 1
            audioPlan.nextSequence = ((try? context.fetch(last).first?.sequence) ?? -1) + 1
        }
        defer { audioPlan.nextSequence += 1 }
        return audioPlan.nextSequence
    }

    /// Notes where the crash-resume point is expected when `work` runs, if it names the source.
    private func planResumePoint(_ work: LibraryAudioWork) {
        if !audioPlan.resumeLoaded {
            audioPlan.resume = ListenResumePointStore.shared.load()
            audioPlan.resumeLoaded = true
        }
        guard let source = work.sourceKey, let target = work.key, var point = audioPlan.resume,
              point.matches(source) else { return }
        work.resumeParagraph = point.paragraph
        work.resumeAt = point.at
        point.articleKey = target.uuidString
        point.paragraph = Self.mapParagraph(point.paragraph, for: work)
        audioPlan.resume = point
    }

    // MARK: - Doing it

    /// Right after a successful save: the stored work in order, the work just planned after any
    /// an earlier launch couldn't finish.
    func doPlannedAudioWork() {
        guard !audioPlan.work.isEmpty else { return }
        let planned = Set(audioPlan.work.map(ObjectIdentifier.init))
        audioPlan = LibraryAudioWorkPlan()
        performStoredWork(planned: planned)
    }

    /// At launch, before anything reads, cleans or renders the audio cache
    /// (`AppComposition.prepareAudioCache`): work a launch saved but didn't finish. Returns how
    /// many records were finished.
    @discardableResult
    func finishAudioWork() -> Int {
        performStoredWork(planned: [])
    }

    /// Does each record, in order, and retires it only once its postconditions hold on disk
    /// (the destination's saved index aligned with its paragraphs and every CAF it lists there,
    /// a merged page's directory gone), whether or not its source still exists: work an app died
    /// in the middle of is simply done again, and every step is idempotent. A record that fails
    /// is kept for the next launch, and so is everything after it (later work can build on it).
    /// `planned`: records this process planned, whose crash target was read in the numbering the
    /// work started from.
    @discardableResult
    private func performStoredWork(planned: Set<ObjectIdentifier>) -> Int {
        let rows: [LibraryAudioWork]
        do {
            rows = try context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))
        } catch {
            log("audio work unreadable, left for the next launch: \(error)")
            return 0
        }
        guard !rows.isEmpty else { return 0 }
        if planned.isEmpty { log("audio work: finishing \(rows.count) left by an earlier launch") }
        var finished = 0
        for row in rows {
            do {
                try perform(row, live: planned.contains(ObjectIdentifier(row)))
            } catch {
                log("audio work \(row.kindRaw) \(Self.short(row.key)) not finished, kept with \(rows.count - finished - 1) after it for the next launch: \(error)")
                ListenTimingLog.log("library_audio_work_failed", [
                    "kind": row.kindRaw, "key": row.key.map(ListenTimingLog.shortKey) ?? "-",
                    "waiting": rows.count - finished, "error": "\(error)",
                ])
                break
            }
            context.delete(row)
            finished += 1
        }
        tts.noteBakeMarksChanged()
        guard finished > 0 else { return 0 }
        do {
            try saveContext(context)
        } catch {
            log("audio work done; its records stay until the next save (done again, harmlessly): \(error)")
        }
        return finished
    }

    private func perform(_ work: LibraryAudioWork, live: Bool) throws {
        switch work.kind {
        case .align: try align(work, live: live)
        case .merge: try merge(work, live: live)
        case nil: log("audio work: unknown kind \(work.kindRaw), dropped")
        }
    }

    /// `key`'s audio is aligned with its rebuilt paragraphs (stamped with the old ones first,
    /// split paragraphs sliced), then its pending render and the resume point follow. Skipped
    /// when the committed page holds other paragraphs now (it changed since this was planned):
    /// aligning with the planned ones could drop audio rendered for what it holds, which is
    /// aligned when the page opens. A page that is gone (merged by a later record, or deleted
    /// with its audio) doesn't stop it.
    private func align(_ work: LibraryAudioWork, live: Bool) throws {
        guard let key = work.key else { return }
        let new = work.paragraphs
        if let page = try context.fetch(LibraryQueries.page(key: key)).first, (page.cachedListenParagraphs ?? []) != new {
            log("audio \(Self.short(key)): the page changed since its layout work was planned; skipped")
            ListenTimingLog.log("library_audio_work", ["kind": "align", "key": ListenTimingLog.shortKey(key), "skipped": "page changed"])
            return
        }
        let cache = tts.audioCache
        if work.stampsSource { try cache.stampMissingHashes(articleID: key, paragraphs: work.sourceParagraphs) }
        let rec = try cache.reconcile(articleID: key, paragraphs: new) { self.tts.chunkPlan(engineID: $0, text: $1) }
        guard cache.isAligned(articleID: key, paragraphs: new) else { throw LibraryAudioWorkError.notAligned(key) }
        let pending = PendingBakeJobStore.shared
        if let job = pending.pendingJobs().first(where: { $0.articleID == key }), job.paragraphs != new {
            let start = ParagraphPositionMap.mapParagraphStart(job.priorityStart, from: ParagraphDocument(parts: job.paragraphs),
                                                               to: ParagraphDocument(parts: new))
            pending.enqueuePending(articleID: key, paragraphs: new, voiceID: job.voiceID,
                                   plan: BakePriorityPlan(priorityStart: start,
                                                          fillGapsFromTopAfterPriority: job.fillGapsFromTopAfterPriority,
                                                          paragraphCount: new.count))
        }
        moveResumePoints(work, live: live)
        ListenTimingLog.log("library_audio_work", [
            "kind": "align", "key": ListenTimingLog.shortKey(key), "leftover": !live,
            "audio_kept": rec.kept, "audio_moved": rec.remapped, "audio_dropped": rec.dropped,
            "audio_sliced": rec.sliced, "audio_misaligned": rec.misaligned,
        ])
        log("audio \(Self.short(key)) aligned: kept \(rec.kept) moved \(rec.remapped) sliced \(rec.sliced) dropped \(rec.dropped)")
    }

    /// The merged page's audio fills the kept page's paragraphs it has none for (by text), its
    /// directory and pending render go, and the resume point, the crash target and the live
    /// session follow onto the kept page. Its audio is aligned with the paragraphs the committed
    /// kept page holds: if they changed since this was planned, the merged audio still finds its
    /// paragraphs by text, but the kept page's is no longer stamped against the planned ones. If
    /// the kept page is gone (deleted since), no page holds the merged audio: it is left to the
    /// cache's age prune, as a deleted page's own would have gone.
    private func merge(_ work: LibraryAudioWork, live: Bool) throws {
        guard let from = work.fromKey, let to = work.key else { return }
        let cache = tts.audioCache
        guard let keeper = try context.fetch(LibraryQueries.page(key: to)).first else {
            if cache.hasDirectory(for: from) { cache.markEphemeral(cacheKey: from) }
            tts.synthQueue.remove(cacheKey: from)
            PendingBakeJobStore.shared.removePending(articleID: from)
            log("audio \(Self.short(from)): the page it merged into is gone; left to the age prune")
            ListenTimingLog.log("library_audio_work", ["kind": "merge", "key": ListenTimingLog.shortKey(to),
                                                       "from": ListenTimingLog.shortKey(from), "skipped": "kept page gone"])
            return
        }
        let paragraphs = keeper.cachedListenParagraphs ?? []
        if work.stampsTarget, !paragraphs.isEmpty, paragraphs == work.paragraphs {
            try cache.stampMissingHashes(articleID: to, paragraphs: paragraphs)
        }
        if work.stampsSource { try cache.stampMissingHashes(articleID: from, paragraphs: work.sourceParagraphs) }
        var rec = ArticleAudioCache.ReconcileResult()
        if paragraphs.isEmpty {
            try cache.rekeyCache(from: from, to: to)
        } else {
            rec = try cache.reconcile(articleID: to, paragraphs: paragraphs, adopting: from) {
                self.tts.chunkPlan(engineID: $0, text: $1)
            }
        }
        guard !cache.hasDirectory(for: from), paragraphs.isEmpty || cache.isAligned(articleID: to, paragraphs: paragraphs) else {
            throw LibraryAudioWorkError.notAligned(to)
        }
        tts.synthQueue.remove(cacheKey: from)
        PendingBakeJobStore.shared.removePending(articleID: from)
        moveResumePoints(work, live: live)
        keyMerged(from, to)
        ListenTimingLog.log("library_audio_work", [
            "kind": "merge", "key": ListenTimingLog.shortKey(to), "from": ListenTimingLog.shortKey(from),
            "audio_adopted": rec.adopted, "leftover": !live,
        ])
        log("audio \(Self.short(from)) merged into \(Self.short(to)): adopted \(rec.adopted)")
    }

    /// The crash-resume file and the crash target launch read from it (or from the crash
    /// marker) follow the work. The file moves only if it is still where the plan found it, so
    /// doing the work again never moves it twice. The target in memory moves with any paragraph
    /// when this process planned the work (it was read before); for work left by an earlier
    /// launch, only if it still holds the file's old point.
    private func moveResumePoints(_ work: LibraryAudioWork, live: Bool) {
        guard let source = work.sourceKey, let target = work.key else { return }
        let map = { (p: Int) in Self.mapParagraph(p, for: work) }
        if let paragraph = work.resumeParagraph, let at = work.resumeAt {
            let store = ListenResumePointStore.shared
            if let point = store.load(), point.matches(source), point.paragraph == paragraph,
               abs(point.at.timeIntervalSince(at)) < 0.001 {
                store.save(article: target, paragraph: map(paragraph), at: point.at)
            }
        }
        guard live || (tts.pendingResume.map { $0.paragraph == work.resumeParagraph } ?? false) else { return }
        tts.remapPendingResume(article: source, to: target, map)
    }

    // MARK: - Positions

    /// A paragraph index on the work's source paragraphs, on its target paragraphs: the same
    /// sentence for a rebuilt page (`align`); for a merge, the kept page's paragraph with the
    /// same text (the nearest, if several), else the same index within its length.
    static func mapParagraph(_ paragraph: Int, for work: LibraryAudioWork) -> Int {
        let from = work.sourceParagraphs, to = work.paragraphs
        switch work.kind {
        case .align:
            guard !to.isEmpty else { return 0 }
            return ParagraphPositionMap.mapParagraphStart(paragraph, from: ParagraphDocument(parts: from),
                                                          to: ParagraphDocument(parts: to))
        case .merge, nil:
            guard !to.isEmpty else { return paragraph }
            if from != to, from.indices.contains(paragraph) {
                let hash = ArticleIdentity.paragraphHash(from[paragraph])
                let same = to.indices.filter { ArticleIdentity.paragraphHash(to[$0]) == hash }
                if let nearest = same.min(by: { abs($0 - paragraph) < abs($1 - paragraph) }) { return nearest }
            }
            return min(max(0, paragraph), to.count - 1)
        }
    }
}
