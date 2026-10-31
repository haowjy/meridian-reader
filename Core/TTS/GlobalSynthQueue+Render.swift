import Foundation

/// The render queue's executor: the policy's plan carried out on the lanes. Each lane runs one
/// model call or one load at a time, in a task of its own; whenever any ends (and on every event
/// that can change the answer, `kickWorker`), the queue offers its candidates for the free lanes
/// again. Hosts asked to go are dropped on free lanes only, never under a call.
extension GlobalSynthQueue {
    /// What runs on a lane now.
    struct LaneWork {
        var work: LaneSnapshot.Work
        /// The paragraph it works on: a call's, or the one a load is for (nil: a preload).
        var unit: ParagraphKey?
    }

    /// Plan again once this turn's events are in: every kick in one turn makes one plan.
    func kickWorker() {
        guard !pumpScheduled, !isPausedForProbe, !isHeldForLaunch, !isPausedForRetry else { return }
        pumpScheduled = true
        Task { [weak self] in
            guard let self else { return }
            self.pumpScheduled = false
            self.pump()
        }
    }

    /// Drop the hosts asked for on the lanes that are free, offer the candidates to the policy,
    /// check its plan, and start each of its actions on its lane.
    private func pump() {
        defer { settleIfIdle() }
        guard let coordinator, !isPausedForProbe, !isHeldForLaunch, !isPausedForRetry else { return }
        applyHostDrops()
        guard laneWork.count < Lane.allCases.count else { return }
        let (offered, situation) = self.situation(coordinator)
        if !offered.isEmpty { preloadEngineID = nil }
        let policy = coordinator.renderPolicy
        let plan = policy.plan(situation)
        if let violation = plan.violation(of: situation) {
            assertionFailure("Render policy \(policy.name): \(violation)")
            ListenTimingLog.log("render_plan_refused", ["policy": policy.name, "why": violation])
            return
        }
        for lane in Lane.allCases {
            guard let action = plan.actions[lane] else { continue }
            switch action {
            case .load(let load):
                if load.candidate == nil { preloadEngineID = nil }
                // Two models wouldn't fit: the other lanes' hosts (free, by the plan check) go first.
                if load.alone {
                    for other in Lane.allCases where other != lane { coordinator.dropHost(on: other, of: nil) }
                }
                begin(.load(load.route), unit: load.candidate.map { key(of: offered[$0]) }, on: lane) {
                    let reason = load.candidate == nil ? "preload" : load.priority == .listener ? "listener" : "work"
                    await $0.load(load.route, reason: reason, priority: load.priority)
                    return true // the queue may have moved during the load: plan again
                }
            case .start(let start):
                let unit = offered[start.candidate]
                begin(.call(start.route, threads: start.threads), unit: key(of: unit), on: lane) {
                    await $0.run(start, of: unit, coordinator)
                }
            }
        }
        // What started is offered no more: a lane still free may take the next unit of the same job.
        if !plan.actions.isEmpty, laneWork.count < Lane.allCases.count { kickWorker() }
        guard laneWork.isEmpty else { return }
        if let hold = plan.held {
            lastBakeEvent = "held: \(hold.label) (resumes when it clears)"
            ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": hold.label])
        } else if !offered.isEmpty {
            let reason = situation.phase == .background && !situation.audioPlaying ? "no_audio_playing" : "idle"
            ListenTimingLog.log("synth_queue_parked", ["phase": runState.phase.rawValue, "reason": reason])
        }
    }

    private func key(of unit: Unit) -> ParagraphKey { ParagraphKey(cacheKey: unit.job.cacheKey, index: unit.index) }

    /// Run `body` as `lane`'s work. When it ends the lane is free again, the hosts asked to go
    /// are dropped, and, unless it returned false (cancelled, or its unit has no voice any more:
    /// the queue waits for the next event), the queue plans again.
    private func begin(_ work: LaneSnapshot.Work, unit: ParagraphKey?, on lane: Lane,
                       _ body: @escaping @MainActor (GlobalSynthQueue) async -> Bool) {
        laneWork[lane] = LaneWork(work: work, unit: unit)
        Task { [weak self] in
            guard let self else { return }
            let goOn = await body(self)
            self.laneWork[lane] = nil
            self.applyHostDrops()
            if goOn { self.kickWorker() } else { self.settleIfIdle() }
        }
    }

    /// Nothing runs on any lane and no plan is due: the background grace ends.
    private func settleIfIdle() {
        #if canImport(UIKit)
        if laneWork.isEmpty, !pumpScheduled { drainGrace.end() }
        #endif
    }

    /// Drop the hosts asked to go (`dropHost`) on the lanes whose work has ended. An engine's
    /// failed-load marks are cleared once none of its drops waits, not when the drop is asked
    /// for: a load in flight then may still fail and mark it, and the rebuild must still get its
    /// fresh try.
    func applyHostDrops() {
        guard let coordinator else { return }
        var dropped = Set<String>()
        for (lane, engines) in hostDrops where laneWork[lane] == nil {
            for engineID in engines { coordinator.dropHost(on: lane, of: engineID) }
            dropped.formUnion(engines)
            hostDrops[lane] = nil
        }
        let waiting = hostDrops.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        for engineID in dropped.subtracting(waiting) {
            failedLoads.subtract(coordinator.routes(for: engineID).map(\.id))
        }
    }

    /// Runs the policy's call on `unit`; false when the queue should wait for the next event
    /// (cancelled, or the unit has no voice any more).
    private func run(_ start: RenderPlan.Start, of unit: Unit, _ coordinator: SynthQueueContext) async -> Bool {
        let (job, index) = (unit.job, unit.index)
        // C138a: the article's own selection, locked by its first render. Never another voice.
        guard let target = coordinator.lockedRenderTarget(for: job.cacheKey) else { return false }
        guard target == unit.target else { return true } // its voice changed since the pick: pick again
        if coordinator.audioCache.audioURL(articleID: job.cacheKey, paragraphIndex: index,
                                           engineID: target.engineID, voiceID: target.cacheVoice) != nil {
            jobs[job.cacheKey]?.missing?.paragraphs.removeAll { $0 == index }
            resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index)
            return true
        }
        guard job.paragraphs.indices.contains(index) else { return true }
        #if canImport(UIKit)
        // The call in flight at backgrounding is done; in the background each call runs under the
        // grace, so iOS suspending the app doesn't cut one short.
        if runState.phase == .background { drainGrace.begin() } else { drainGrace.end() }
        #endif
        do {
            try Task.checkCancellation()
            try await renderOrStitch(job, paragraph: index, in: target, start: start)
        } catch is CancellationError {
            failWaiters(cacheKey: job.cacheKey, index: index, error: CancellationError())
            return false
        } catch where !start.route.lane.runsInBackground && runState.phase == .background {
            // The app left the front during the call: not the paragraph's failure. Its waiters
            // keep waiting; a lane that runs in the background renders it.
            ListenTimingLog.log("call_left_front", ["key": ListenTimingLog.shortKey(job.cacheKey), "p": index,
                                                    "route": start.route.id, "err": error.localizedDescription])
        } catch {
            // The engine failed (or stitch/store failed). Don't hot-loop.
            failedUnits.insert(failedID(job.cacheKey, index, job.paragraphHashes[index]))
            let failMsg = "bake FAIL \(job.cacheKey.uuidString.prefix(8)) p\(index): \(error.localizedDescription)"
            lastBakeEvent = failMsg
            ListenDebugLog.shared.append(failMsg)
            ListenTimingLog.log("paragraph_failed", [
                "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "err": error.localizedDescription,
            ])
            failWaiters(cacheKey: job.cacheKey, index: index, error: error)
        }
        return true
    }

    /// What the policy decides from: the candidates (with the queue's units behind them, same
    /// indices), the phase, the hold, each lane's work and resident route, the memory left.
    private func situation(_ coordinator: SynthQueueContext) -> ([Unit], RenderSituation) {
        let offered = candidates()
        var lanes: [Lane: LaneSnapshot] = [:]
        for lane in Lane.allCases {
            lanes[lane] = LaneSnapshot(work: laneWork[lane]?.work, resident: coordinator.residentRoute(on: lane))
        }
        let situation = RenderSituation(
            phase: runState.phase, audioPlaying: coordinator.playingCacheKey != nil,
            hold: bakeConditions().bakeAheadHold, preload: preloadEngineID.map(coordinator.routes(for:)) ?? [],
            candidates: offered.map {
                RenderCandidate(item: $0.job.cacheKey, paragraph: $0.index, demand: $0.demand,
                                engine: SpeechEngineID(rawValue: $0.target.engineID), routes: $0.routes)
            },
            lanes: lanes, cores: ProcessInfo.processInfo.activeProcessorCount,
            availableMemoryMB: ProcessMemory.availableMB)
        return (offered, situation)
    }

    /// Renders one chunk of the paragraph (one a listener waits for first, else the next in
    /// order), or, once every chunk is on disk, stitches them and publishes the paragraph. At most
    /// one model call, so the policy weighs priority again between chunks. The paragraph is its
    /// lane's alone meanwhile (`paragraphsInCalls`), so it is published once.
    private func renderOrStitch(_ job: ArticleJob, paragraph index: Int, in target: RenderTarget,
                                start: RenderPlan.Start) async throws {
        let priority = start.priority
        guard let coordinator else { throw CancellationError() }
        let cache = coordinator.audioCache
        let text = job.paragraphs[index]
        let hash = job.paragraphHashes[index]
        // Never empty: a paragraph with nothing to speak is never missing.
        let chunks = coordinator.chunkPlans.chunks(for: text, engineID: target.engineID) ?? []
        let chunkURLs = chunks.indices.map {
            cache.chunkURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                           voice: target.cacheVoice, chunk: $0)
        }
        // A listener waiting on a later chunk (scrubbed to a sentence mid-paragraph) gets that
        // chunk first; otherwise chunks render in order.
        let waited = chunkWaiters.keys
            .filter { $0.cacheKey == job.cacheKey && $0.index == index }
            .map(\.chunk).sorted()
            .first { chunkURLs.indices.contains($0) && !cache.isUsableAudioFile(chunkURLs[$0]) }
        if let k = waited ?? chunkURLs.firstIndex(where: { !cache.isUsableAudioFile($0) }) {
            let audio = try await renderChunk(job: job, index: index, chunk: k, of: chunks.count,
                                              text: chunks[k], next: k + 1 < chunks.count ? chunks[k + 1] : nil,
                                              to: chunkURLs[k], for: target, start: start)
            backgroundWindow.noteChunk(route: start.route.id, audioSeconds: audio ?? 0)
            // The engine or voice changed during the call: the chunk is filed under its own
            // voice, and its waiters wait for the new voice's render.
            guard audio != nil, coordinator.renderTarget(for: job.cacheKey) == target else { return }
            resumeChunkWaiters(cacheKey: job.cacheKey, index: index, chunk: k, url: chunkURLs[k])
            guard chunkURLs.allSatisfy(cache.isUsableAudioFile) else { return }
        }
        // All chunks present → stitch them off the main actor (a read / convert / write of the
        // whole paragraph) into a file of their own, then publish it here only if the queue still
        // wants this text on this paragraph, in this voice. Meanwhile the article's audio may have
        // been aligned with other paragraphs (opening it with newer text, a merge) and its job
        // given them, the article left the queue (audio cleared, deleted, rekeyed), or the voice
        // changed: a render of the old paragraph or voice isn't filed on the new one.
        let stitching = cache.stitchingURL(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                                           voice: target.cacheVoice)
        let stitched: ChunkAudioStitcher.Result
        do {
            stitched = try await Task.detached(priority: priority.taskPriority) {
                try ArticleAudioCache.stitchParagraph(chunkURLs, to: stitching)
            }.value
        } catch where !chunkURLs.allSatisfy(cache.isUsableAudioFile) {
            // The chunk scratch went away meanwhile (identity prep): not this paragraph's failure —
            // look again.
            try? FileManager.default.removeItem(at: stitching)
            return
        }
        guard stillWants(job.cacheKey, index, hash), coordinator.renderTarget(for: job.cacheKey) == target,
              cache.isUsableAudioFile(stitching) else {
            try? FileManager.default.removeItem(at: stitching)
            ListenTimingLog.log("paragraph_discarded", ["key": ListenTimingLog.shortKey(job.cacheKey), "p": index])
            return
        }
        let changesBefore = cache.indexChanges(of: job.cacheKey)
        try cache.publishParagraph(
            staged: stitching,
            articleID: job.cacheKey,
            paragraphIndex: index,
            duration: stitched.duration,
            engineID: target.engineID,
            voiceID: target.cacheVoice,
            textHash: hash,
            chunkDurations: chunks.count > 1 ? stitched.chunkDurations : nil
        )
        jobs[job.cacheKey]?.noteRendered(index, in: target, changes: changesBefore,
                                         after: cache.indexChanges(of: job.cacheKey))
        coordinator.noteBakeMarksChanged(of: job.cacheKey)
        if job.isEphemeral {
            do { try cache.markEphemeral(cacheKey: job.cacheKey, lastAccess: Date()) } catch {
                ListenDebugLog.shared.append("ephemeral mark failed \(job.cacheKey.uuidString.prefix(8)): \(error.localizedDescription)")
            }
        }
        if !liveChunkParagraphs.contains(ParagraphKey(cacheKey: job.cacheKey, index: index)) {
            try? FileManager.default.removeItem(
                at: cache.chunkDirectory(articleID: job.cacheKey, paragraphIndex: index, textHash: hash,
                                         voice: target.cacheVoice))
        }
        resumeChunkWaitersWithParagraph(cacheKey: job.cacheKey, index: index)
        let readyMsg = "bake ok \(job.cacheKey.uuidString.prefix(8)) p\(index) (\(chunks.count) chunk\(chunks.count == 1 ? "" : "s"))"
        lastBakeEvent = readyMsg
        ListenDebugLog.shared.append(readyMsg)
        ListenTimingLog.log("paragraph_ready", [
            "key": ListenTimingLog.shortKey(job.cacheKey), "p": index, "chunks": chunks.count,
            "chars": text.count, "audio_s": (stitched.duration * 100).rounded() / 100,
            "primary": stack.first == job.cacheKey, "route": start.route.id,
        ])
    }

    /// Load a host for `route` on its lane (the queue's alone; see the type's notes). A CPU-lane
    /// load that fails or is cancelled fails the chunks listeners wait for in its engine, and its
    /// jobs wait (`failedLoads`). Another lane's failed load only takes that route out: the CPU
    /// lane, every engine's fallback, goes on with its work (and a load cut by the app leaving the
    /// front isn't marked at all).
    private func load(_ route: RenderRoute, reason: String, priority: RenderPriority) async {
        guard let coordinator else { return }
        let engineID = route.engine.rawValue
        let t0 = ListenTimingLog.now()
        ListenTimingLog.log("engine_load", ["engine": engineID, "route": route.id, "reason": reason, "op": "start",
                                            "qos": priority == .listener ? "userInitiated" : "utility",
                                            "replaces": coordinator.residentRoute(on: route.lane)?.id ?? "-"])
        do {
            try await coordinator.makeResident(route, priority: priority)
            ListenTimingLog.log("engine_load", ["engine": engineID, "route": route.id, "reason": reason, "op": "ready",
                                                "ms": ListenTimingLog.ms(since: t0)])
        } catch {
            ListenTimingLog.log("engine_load", ["engine": engineID, "route": route.id, "reason": reason, "op": "failed",
                                                "ms": ListenTimingLog.ms(since: t0), "err": error.localizedDescription])
            if !route.lane.runsInBackground, runState.phase == .background { return }
            failedLoads.insert(route.id)
            lastBakeEvent = "\(route.id) didn’t load: \(error.localizedDescription)"
            ListenDebugLog.shared.append(lastBakeEvent)
            guard route.lane == .cpu else { return }
            for key in Set(chunkWaiters.keys.map(\.cacheKey))
            where coordinator.renderTarget(for: key)?.engineID == engineID {
                failWaiters(cacheKey: key, error: error)
            }
        }
    }

    /// The engine renders the chunk (recursive re-split inside the renderer) on the start's route,
    /// at its threads and QoS; returns its audio's seconds, or throws when it fails. Returns nil,
    /// writing nothing, when the engine fails because `target` went away or changed during the
    /// call (the next step renders what renders now).
    private func renderChunk(
        job: ArticleJob, index: Int, chunk: Int, of count: Int, text: String, next: String? = nil,
        to url: URL, for target: RenderTarget, start: RenderPlan.Start
    ) async throws -> TimeInterval? {
        guard let coordinator else { throw CancellationError() }
        let t0 = ListenTimingLog.now()
        let request = ChunkRenderRequest(
            article: job.cacheKey, paragraph: index, chunk: chunk, isLastInParagraph: chunk == count - 1,
            nextWord: next?.split(separator: " ").first.map(String.init), priority: start.priority,
            threads: start.threads, isPrimary: stack.first == job.cacheKey, voice: target.engineVoice)
        let ctx = request.logFields
        do {
            let duration = try await coordinator.synthRenderer.renderChunkToFile(
                text: text, destination: url, route: start.route, request: request)
            ListenTimingLog.log("chunk_ready", ctx.merging([
                "n": count, "chars": text.count, "ms": ListenTimingLog.ms(since: t0),
                "audio_s": (duration * 100).rounded() / 100, "route": start.route.id,
            ]) { a, _ in a })
            return duration
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard coordinator.renderTarget(for: job.cacheKey) == target else { return nil }
            // The unit fails; the player pauses there (C129: never another voice).
            let msg = "\(start.route.id) FAIL p\(index) c\(chunk): \(error.localizedDescription)"
            ListenDebugLog.shared.append(msg)
            lastBakeEvent = msg
            throw error
        }
    }
}
