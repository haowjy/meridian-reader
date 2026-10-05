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

    /// Right after a successful save: the work planned with it, in order.
    func doPlannedAudioWork() {
        guard !audioPlan.work.isEmpty else { return }
        let work = audioPlan.work.sorted { $0.sequence < $1.sequence }
        audioPlan = LibraryAudioWorkPlan()
        perform(work, live: true)
    }

    /// At launch, before the library's other maintenance: work a launch saved but didn't finish.
    @discardableResult
    func finishAudioWork() -> Int {
        let left = (try? context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
        guard !left.isEmpty else { return 0 }
        log("audio work: finishing \(left.count) left by an earlier launch")
        perform(left, live: false)
        return left.count
    }

    /// `live`: planned by this process, so the crash target it read at launch is in the
    /// numbering the work started from.
    private func perform(_ work: [LibraryAudioWork], live: Bool) {
        for item in work {
            switch item.kind {
            case .align: align(item, live: live)
            case .merge: merge(item, live: live)
            case nil: log("audio work: unknown kind \(item.kindRaw), dropped")
            }
            context.delete(item)
        }
        tts.noteBakeMarksChanged()
        do {
            try saveContext(context)
        } catch {
            log("audio work done; its records stay until the next save (done again, harmlessly): \(error)")
        }
    }

    private func align(_ work: LibraryAudioWork, live: Bool) {
        guard let key = work.key else { return }
        let new = work.paragraphs
        let cache = tts.audioCache
        var split = ArticleAudioCache.SplitRemapResult()
        var rec = ArticleAudioCache.ReconcileResult()
        if cache.hasCache(for: key) {
            if work.stampsSource { cache.stampMissingHashes(articleID: key, paragraphs: work.sourceParagraphs) }
            split = cache.remapSplitParagraphs(articleID: key, paragraphs: new) { self.tts.chunkPlan(engineID: $0, text: $1) }
            rec = cache.reconcile(articleID: key, paragraphs: new)
        }
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
            "audio_sliced": split.sliced, "audio_misaligned": split.misaligned,
        ])
        log("audio \(Self.short(key)) aligned: kept \(rec.kept) moved \(rec.remapped) sliced \(split.sliced) dropped \(rec.dropped)")
    }

    private func merge(_ work: LibraryAudioWork, live: Bool) {
        guard let from = work.fromKey, let to = work.key else { return }
        let cache = tts.audioCache
        let hadAudio = cache.hasCache(for: from)
        if hadAudio {
            let paragraphs = work.paragraphs
            if work.stampsTarget, !paragraphs.isEmpty { cache.stampMissingHashes(articleID: to, paragraphs: paragraphs) }
            if work.stampsSource { cache.stampMissingHashes(articleID: from, paragraphs: work.sourceParagraphs) }
            try? cache.rekeyCache(from: from, to: to)
            if !paragraphs.isEmpty { cache.reconcile(articleID: to, paragraphs: paragraphs) }
        }
        tts.synthQueue.remove(cacheKey: from)
        PendingBakeJobStore.shared.removePending(articleID: from)
        moveResumePoints(work, live: live)
        keyMerged(from, to)
        ListenTimingLog.log("library_audio_work", [
            "kind": "merge", "key": ListenTimingLog.shortKey(to), "from": ListenTimingLog.shortKey(from),
            "had_audio": hadAudio, "leftover": !live,
        ])
        log("audio \(Self.short(from)) merged into \(Self.short(to))")
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
