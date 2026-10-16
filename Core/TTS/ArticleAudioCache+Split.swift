import AVFoundation
import Foundation

// MARK: - Giant-paragraph split (paragraph layout v3)

extension ArticleAudioCache {
    /// For units whose paragraph is now split into consecutive `paragraphs[j..<j+m]` (found by
    /// text hash: the hash ignores whitespace, so the pieces joined by " " hash like the old
    /// paragraph), the pieces whose own chunk plan equals a contiguous run of the old paragraph's
    /// chunks, cut out of the old CAF (sample-exact, at the chunk boundaries recorded in
    /// `chunkDurations`) into new `s-` files in `dir`, as units on their new paragraph. A piece
    /// some unit already has audio for is skipped; the others are left missing (they re-render).
    /// Part of `reconcile`, which places these first and drops the old split CAFs.
    /// `chunkPlan(engineID, text)` must be the render queue's plan (`ChunkPlans`); nil = don't slice.
    func slices(of units: [AlignUnit], paragraphs: [String], into dir: URL,
                chunkPlan: ((String, String) -> [String]?)?, _ result: inout ReconcileResult) throws -> [AlignUnit] {
        guard let chunkPlan, paragraphs.count > 1 else { return [] }
        let current = Set(paragraphs.map(ArticleIdentity.paragraphHash))
        let orphans = units.filter {
            guard let h = $0.entry.textHash, !current.contains(h), let d = $0.entry.chunkDurations, d.count > 1 else { return false }
            return true
        }
        guard !orphans.isEmpty else { return [] }
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
        var have = Set(units.compactMap(\.entry.textHash))
        var slices: [AlignUnit] = []
        for old in orphans {
            guard let hash = old.entry.textHash, let run = runs[hash], let durations = old.entry.chunkDurations else { continue }
            result.splitParagraphs += 1
            let pieces = Array(paragraphs[run.start..<(run.start + run.count)])
            guard let oldPlan = chunkPlan(old.engineID, pieces.joined(separator: " ")), oldPlan.count == durations.count
            else { result.misaligned += pieces.count; continue }
            var from = 0
            for (i, piece) in pieces.enumerated() {
                let target = run.start + i
                guard let plan = chunkPlan(old.engineID, piece), !plan.isEmpty,
                      let q = Self.firstMatch(of: plan, in: oldPlan, from: from) else {
                    result.misaligned += 1
                    continue
                }
                from = q + plan.count
                let pieceHash = ArticleIdentity.paragraphHash(piece)
                guard !have.contains(pieceHash) else { continue }
                let start = durations[..<q].reduce(0, +)
                let length = durations[q..<(q + plan.count)].reduce(0, +)
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(String(format: "s-%04d-", target) + UUID().uuidString.prefix(8) + ".caf")
                guard try Self.slice(old.url, start: start, duration: length, to: url), isUsableAudioFile(url) else {
                    result.misaligned += 1
                    continue
                }
                let entry = IndexFile.ParagraphEntry(index: target, file: url.lastPathComponent, duration: length,
                                                     textHash: pieceHash,
                                                     chunkDurations: plan.count > 1 ? Array(durations[q..<(q + plan.count)]) : nil)
                slices.append(AlignUnit(entry: entry, engineID: old.engineID, voiceID: old.voiceID, url: url, origin: .slice))
                have.insert(pieceHash)
                result.sliced += 1
            }
        }
        return slices
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
    /// False when the source can't be read there (nothing to keep); throws when the copy can't be
    /// written.
    static func slice(_ src: URL, start: Double, duration: Double, to dst: URL) throws -> Bool {
        guard let file = try? AVAudioFile(forReading: src, commonFormat: .pcmFormatInt16, interleaved: true) else { return false }
        let sr = file.processingFormat.sampleRate
        let a = AVAudioFramePosition((start * sr).rounded())
        guard a >= 0, a < file.length else { return false }
        let count = AVAudioFrameCount(max(0, min(Double(file.length - a), (duration * sr).rounded())))
        guard count > 0, let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return false }
        file.framePosition = a
        guard (try? file.read(into: buf, frameCount: count)) != nil else { return false }
        if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
        let out = try AVAudioFile(forWriting: dst, settings: file.fileFormat.settings,
                                  commonFormat: .pcmFormatInt16, interleaved: true)
        try out.write(from: buf)
        return true
    }
}
