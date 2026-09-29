import AVFoundation
import Foundation

// MARK: - Giant-paragraph split (paragraph layout v3, 2026-09-25)

extension ArticleAudioCache {
    struct SplitRemapResult: Equatable {
        /// Old paragraph CAFs whose text is now several paragraphs.
        var splitParagraphs = 0
        /// New paragraphs cut out of an old CAF (their chunk plan matched the old chunks exactly).
        var sliced = 0
        /// New paragraphs whose chunk plan didn't line up (will re-render).
        var misaligned = 0
    }

    /// For cached paragraphs that are now split into consecutive `paragraphs[j..<j+m]` (found by
    /// text hash: the hash ignores whitespace, so the pieces joined by " " hash like the old
    /// paragraph), keep audio only where it lines up cleanly: a piece whose own chunk plan equals a
    /// contiguous run of the old paragraph's chunks is cut out of the old CAF (sample-exact, at
    /// the chunk boundaries recorded in `chunkDurations`) and stored as that piece's paragraph.
    /// Other pieces are left missing (they re-render). Call `reconcile` right after: it moves the
    /// unchanged paragraphs to their shifted indices and drops the old split CAFs.
    /// `chunkPlan(engineID, text)` must be the render queue's plan; nil = don't slice.
    @discardableResult
    func remapSplitParagraphs(articleID: UUID, paragraphs: [String],
                              chunkPlan: (String, String) -> [String]?) -> SplitRemapResult {
        var result = SplitRemapResult()
        guard var index = try? loadIndex(for: articleID), !index.paragraphs.isEmpty, paragraphs.count > 1 else {
            return result
        }
        let current = Set(paragraphs.map(ArticleIdentity.paragraphHash))
        let orphans = index.paragraphs.filter {
            guard let h = $0.textHash, !current.contains(h), let d = $0.chunkDurations, d.count > 1 else { return false }
            return true
        }
        guard !orphans.isEmpty else { return result }
        // Runs of 2…8 consecutive paragraphs that together exceed the split threshold.
        var runs: [String: (start: Int, count: Int)] = [:]
        for j in paragraphs.indices {
            var joined = paragraphs[j]
            for m in 2...8 where j + m - 1 < paragraphs.count {
                joined += " " + paragraphs[j + m - 1]
                guard joined.count > ParagraphSplitter.threshold else { continue }
                let h = ArticleIdentity.paragraphHash(joined)
                if runs[h] == nil { runs[h] = (j, m) }
            }
        }
        let dir = directory(for: articleID)
        var added: [IndexFile.ParagraphEntry] = []
        for old in orphans {
            guard let hash = old.textHash, let run = runs[hash], let durations = old.chunkDurations else { continue }
            result.splitParagraphs += 1
            let pieces = Array(paragraphs[run.start..<(run.start + run.count)])
            let engine = index.engine(of: old)
            guard let oldPlan = chunkPlan(engine, pieces.joined(separator: " ")), oldPlan.count == durations.count
            else { result.misaligned += pieces.count; continue }
            var from = 0
            for (i, piece) in pieces.enumerated() {
                let target = run.start + i
                guard let plan = chunkPlan(engine, piece), !plan.isEmpty,
                      let q = Self.firstMatch(of: plan, in: oldPlan, from: from) else {
                    result.misaligned += 1
                    continue
                }
                from = q + plan.count
                let start = durations[..<q].reduce(0, +)
                let length = durations[q..<(q + plan.count)].reduce(0, +)
                let name = "s-\(String(format: "%04d", target))-\(UUID().uuidString.prefix(8)).caf"
                guard Self.slice(dir.appendingPathComponent(old.file), start: start, duration: length,
                                 to: dir.appendingPathComponent(name)) else {
                    result.misaligned += 1
                    continue
                }
                var e = IndexFile.ParagraphEntry(index: target, file: name, duration: length,
                                                 textHash: ArticleIdentity.paragraphHash(piece),
                                                 chunkDurations: plan.count > 1 ? Array(durations[q..<(q + plan.count)]) : nil)
                e.engineID = old.engineID
                e.voiceID = old.voiceID
                added.append(e)
                result.sliced += 1
            }
        }
        guard !added.isEmpty else { return result }
        // Sliced entries go first so `reconcile` gives them their slot (exact hash at index).
        index.paragraphs = added + index.paragraphs
        try? JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        return result
    }

    private static func firstMatch(of plan: [String], in old: [String], from: Int) -> Int? {
        guard plan.count <= old.count else { return nil }
        var q = from
        while q + plan.count <= old.count {
            if Array(old[q..<(q + plan.count)]) == plan { return q }
            q += 1
        }
        return nil
    }

    /// Copy [start, start+duration) of a CAF into a new CAF, sample-exact (Int16, no resampling).
    static func slice(_ src: URL, start: Double, duration: Double, to dst: URL) -> Bool {
        do {
            let file = try AVAudioFile(forReading: src, commonFormat: .pcmFormatInt16, interleaved: true)
            let sr = file.processingFormat.sampleRate
            let a = AVAudioFramePosition((start * sr).rounded())
            let count = AVAudioFrameCount(min(Double(file.length - a), (duration * sr).rounded()))
            guard a >= 0, a < file.length, count > 0,
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return false }
            file.framePosition = a
            try file.read(into: buf, frameCount: count)
            if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
            let out = try AVAudioFile(forWriting: dst, settings: file.fileFormat.settings,
                                      commonFormat: .pcmFormatInt16, interleaved: true)
            try out.write(from: buf)
            return true
        } catch {
            return false
        }
    }
}
