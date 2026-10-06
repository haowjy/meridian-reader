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
    case notDeleted(UUID)
    case notEphemeral(UUID)
    case notSaved(UUID)
}

/// What a run of the stored audio work did: how many records it retired, and the audio the
/// records it left waiting need: the pages the one that failed and every one after it touch, or
/// all of it when the records couldn't be read.
struct LibraryAudioWorkOutcome: Equatable {
    var finished = 0
    var held = ArticleAudioCache.Hold.nothing
}

/// Files outside the library store change only after the library change they belong to is saved.
/// The layout pass, dedupe, deleting pages (a book's *Replace* dropping chapters among them),
/// pages leaving the Library and Save plan their audio work (`planAlign`, `planMerge`,
/// `planDelete`, `planEphemeral`, `planSaved`) as records in the same save; `commit` does it once
/// the save succeeds, after any work an earlier launch left, and retires each record once its
/// postconditions hold; the next launch finishes whatever is left (`finishAudioWork`); a save that
/// fails and is rolled back (`rollBack`) leaves every file alone. Work that waited acts on the
/// pages as they are when it runs: by then a key can belong to a later page (saved, deleted, then
/// played again without saving), whose audio it keeps.
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

    /// The deleted page's audio, pending render and queued renders go once the delete is saved,
    /// in order after the work recorded before it: audio that earlier work still needs (a merge
    /// from this page, a layout pass on it) is never deleted first, and while that work waits the
    /// page stays held with it.
    func planDelete(key: UUID) {
        let work = LibraryAudioWork(sequence: nextAudioWorkSequence(), kind: .delete, key: key,
                                    paragraphs: [], sourceParagraphs: [])
        context.insert(work)
        audioPlan.work.append(work)
    }

    /// The page left the Library (*Remove from Library*, unsave): once that is saved, its audio
    /// goes back on the ephemeral TTL, in order after the work recorded before it.
    func planEphemeral(key: UUID) {
        let work = LibraryAudioWork(sequence: nextAudioWorkSequence(), kind: .ephemeral, key: key,
                                    paragraphs: [], sourceParagraphs: [])
        context.insert(work)
        audioPlan.work.append(work)
    }

    /// The page was saved to the Library: once that is saved, its audio is marked saved and its
    /// queued render non-ephemeral, in order after the work recorded before it.
    func planSaved(key: UUID) {
        let work = LibraryAudioWork(sequence: nextAudioWorkSequence(), kind: .saved, key: key,
                                    paragraphs: [], sourceParagraphs: [])
        context.insert(work)
        audioPlan.work.append(work)
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
        point.paragraph = Self.mapParagraph(point.paragraph, for: work, onto: work.paragraphs)
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
    /// many records were finished and the audio the rest leave waiting, which the cache holds
    /// meanwhile (`ArticleAudioCache.held`).
    @discardableResult
    func finishAudioWork() -> LibraryAudioWorkOutcome {
        performStoredWork(planned: [])
    }

    /// Does each record, in order, and retires it only once its postconditions hold on disk
    /// (the destination's saved index aligned with its paragraphs and every CAF it lists there,
    /// a merged page's directory gone), whether or not its source still exists: work an app died
    /// in the middle of is simply done again, and every step is idempotent. A record that fails
    /// is kept for the next launch, and so is everything after it (later work can build on it);
    /// the pages they touch, source and destination, are held in the audio cache until a run
    /// finishes them: the engine purges and the prune leave their audio alone, and their saved
    /// bake jobs aren't adopted. Records that can't be read may need any page's audio, so all
    /// of it is held until a run reads them. `planned`: records this process planned, whose crash
    /// target was read in the numbering the work started from.
    @discardableResult
    private func performStoredWork(planned: Set<ObjectIdentifier>) -> LibraryAudioWorkOutcome {
        var outcome = LibraryAudioWorkOutcome()
        defer { tts.audioCache.held = outcome.held }
        let rows: [LibraryAudioWork]
        do {
            rows = try fetchAudioWork(context)
        } catch {
            outcome.held = .all
            log("audio work unreadable, all audio held from the purges, the prune and bakes until it reads: \(error)")
            ListenTimingLog.log("library_audio_work_unreadable", ["error": "\(error)"])
            return outcome
        }
        guard !rows.isEmpty else { return outcome }
        if planned.isEmpty { log("audio work: finishing \(rows.count) left by an earlier launch") }
        for row in rows {
            do {
                try perform(row, live: planned.contains(ObjectIdentifier(row)))
            } catch {
                let waiting = rows[outcome.finished...]
                let keys = Set(waiting.flatMap { [$0.key, $0.fromKey].compactMap { $0 } })
                outcome.held = .pages(keys)
                log("audio work \(row.kindRaw) \(Self.short(row.key)) not finished, kept with \(waiting.count - 1) after it for the next launch: \(error)")
                ListenTimingLog.log("library_audio_work_failed", [
                    "kind": row.kindRaw, "key": row.key.map(ListenTimingLog.shortKey) ?? "-",
                    "waiting": waiting.count, "held": keys.count, "error": "\(error)",
                ])
                break
            }
            context.delete(row)
            outcome.finished += 1
        }
        tts.noteBakeMarksChanged()
        guard outcome.finished > 0 else { return outcome }
        do {
            try saveChanges()
        } catch {
            log("audio work done; its records stay until the next save (done again, harmlessly): \(error)")
        }
        return outcome
    }

    private func perform(_ work: LibraryAudioWork, live: Bool) throws {
        switch work.kind {
        case .align: try align(work, live: live)
        case .merge: try merge(work, live: live)
        case .delete: try deleteAudio(work)
        case .ephemeral: try releaseAudio(work)
        case .saved: try keepAudio(work)
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
        moveResumePoints(work, onto: new, live: live)
        ListenTimingLog.log("library_audio_work", [
            "kind": "align", "key": ListenTimingLog.shortKey(key), "leftover": !live,
            "audio_kept": rec.kept, "audio_moved": rec.remapped, "audio_dropped": rec.dropped,
            "audio_sliced": rec.sliced, "audio_misaligned": rec.misaligned,
        ])
        log("audio \(Self.short(key)) aligned: kept \(rec.kept) moved \(rec.remapped) sliced \(rec.sliced) dropped \(rec.dropped)")
    }

    /// The merged page's audio fills the kept page's paragraphs it has none for (by text), its
    /// directory and pending render go, and the resume point, the crash target and the live
    /// session follow onto the kept page. Its audio and the resume point are aligned with the
    /// paragraphs the committed kept page holds: if they changed since this was planned, the
    /// merged audio and the resume point still find their paragraphs by text, but the kept page's
    /// audio is no longer stamped against the planned ones. If
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
        moveResumePoints(work, onto: paragraphs, live: live)
        keyMerged(from, to)
        ListenTimingLog.log("library_audio_work", [
            "kind": "merge", "key": ListenTimingLog.shortKey(to), "from": ListenTimingLog.shortKey(from),
            "audio_adopted": rec.adopted, "leftover": !live,
        ])
        log("audio \(Self.short(from)) merged into \(Self.short(to)): adopted \(rec.adopted)")
    }

    /// The deleted page's audio directory, pending render and queued renders go. When a page with
    /// its key exists again (a later change brought it back while this waited), the audio is that
    /// page's now: kept, and saved or ephemeral as that page is (`settleAudio`).
    private func deleteAudio(_ work: LibraryAudioWork) throws {
        guard let key = work.key else { return }
        if let page = try context.fetch(LibraryQueries.page(key: key)).first {
            log("audio \(Self.short(key)): its page is back since it was deleted; kept")
            ListenTimingLog.log("library_audio_work", ["kind": "delete", "key": ListenTimingLog.shortKey(key), "skipped": "page back"])
            try settleAudio(key, page: page)
            return
        }
        try tts.clearListenAudio(for: key)
        guard !tts.audioCache.hasDirectory(for: key) else { throw LibraryAudioWorkError.notDeleted(key) }
        ListenTimingLog.log("library_audio_work", ["kind": "delete", "key": ListenTimingLog.shortKey(key)])
        log("audio \(Self.short(key)) deleted with its page")
    }

    /// The page left the Library: its audio goes back on the ephemeral TTL (kept, so playback
    /// goes on; the cache's age prune removes it), unless the page is saved in the Library again
    /// by the time this runs (`settleAudio`).
    private func releaseAudio(_ work: LibraryAudioWork) throws {
        guard let key = work.key else { return }
        try settleAudio(key, page: try context.fetch(LibraryQueries.page(key: key)).first)
        ListenTimingLog.log("library_audio_work", ["kind": "ephemeral", "key": ListenTimingLog.shortKey(key)])
    }

    /// The page was saved: its audio is saved audio, out of the ephemeral TTL, and its queued
    /// render no longer ephemeral, unless the page has left the Library by the time this runs
    /// (`settleAudio`).
    private func keepAudio(_ work: LibraryAudioWork) throws {
        guard let key = work.key else { return }
        try settleAudio(key, page: try context.fetch(LibraryQueries.page(key: key)).first)
        ListenTimingLog.log("library_audio_work", ["kind": "saved", "key": ListenTimingLog.shortKey(key)])
    }

    /// `key`'s audio as the page holding the key is now, not as it was when the work was
    /// planned: a key can belong to a later page by the time the work runs (saved, deleted, then
    /// played again without saving), and its renders are that page's. Saved audio for a page
    /// saved in the Library (a page with no audio yet has none to mark); for any other page, or
    /// none, the ephemeral TTL, with the address the page has now. The files stay either way.
    private func settleAudio(_ key: UUID, page: Page?) throws {
        let cache = tts.audioCache
        if page?.isSavedToLibrary == true {
            tts.migrateListenCache(from: key, to: key)
            guard !cache.hasDirectory(for: key) || cache.loadMeta(for: key)?.kind == .saved else {
                throw LibraryAudioWorkError.notSaved(key)
            }
            log("audio \(Self.short(key)) saved with its page")
        } else {
            tts.markListenCacheEphemeral(key, canonicalURL: page?.canonicalURL)
            guard cache.loadMeta(for: key)?.kind == .ephemeral else { throw LibraryAudioWorkError.notEphemeral(key) }
            log("audio \(Self.short(key)) on the ephemeral TTL (\(page == nil ? "no page" : "not saved in the Library"))")
        }
    }

    /// The crash-resume file and the crash target launch read from it (or from the crash
    /// marker) follow the work, onto `paragraphs`: the destination's paragraphs its audio was
    /// just aligned with (for a merge, what the kept page holds now, which may differ from what
    /// was planned). The file moves only if it is still where the plan found it, so doing the
    /// work again never moves it twice. The target in memory moves with any paragraph when this
    /// process planned the work (it was read before); for work left by an earlier launch, only if
    /// it still holds the file's old point.
    private func moveResumePoints(_ work: LibraryAudioWork, onto paragraphs: [String], live: Bool) {
        guard let source = work.sourceKey, let target = work.key else { return }
        let map = { (p: Int) in Self.mapParagraph(p, for: work, onto: paragraphs) }
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

    /// A paragraph index on the work's source paragraphs, on the destination's paragraphs `to`:
    /// the same sentence for a rebuilt page (`align`); for a merge, the kept page's paragraph
    /// with the same text (the nearest, if several), else the same index within its length.
    static func mapParagraph(_ paragraph: Int, for work: LibraryAudioWork, onto to: [String]) -> Int {
        let from = work.sourceParagraphs
        switch work.kind {
        case .align:
            guard !to.isEmpty else { return 0 }
            return ParagraphPositionMap.mapParagraphStart(paragraph, from: ParagraphDocument(parts: from),
                                                          to: ParagraphDocument(parts: to))
        case .merge, .delete, .ephemeral, .saved, nil:
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
