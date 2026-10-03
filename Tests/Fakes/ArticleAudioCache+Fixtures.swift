import Foundation
@testable import Reader

extension ArticleAudioCache {
    struct EmptyFixtureAudio: Error {}

    /// Test setup: put an already rendered CAF in place as paragraph `paragraphIndex` and index
    /// it, as a finished bake would.
    @discardableResult
    func storeParagraph(
        articleID: UUID,
        paragraphIndex: Int,
        sourceURL: URL,
        duration: TimeInterval,
        engineID: String,
        voiceID: String,
        text: String? = nil,
        chunkDurations: [Double]? = nil
    ) throws -> URL {
        guard isUsableAudioFile(sourceURL) else { throw EmptyFixtureAudio() }
        let fm = FileManager.default
        try fm.createDirectory(at: directory(for: articleID), withIntermediateDirectories: true)
        let dest = paragraphFileURL(articleID: articleID, paragraphIndex: paragraphIndex)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: sourceURL, to: dest)
        try recordParagraph(articleID: articleID, paragraphIndex: paragraphIndex, duration: duration,
                            engineID: engineID, voiceID: voiceID, textHash: text.map(ArticleIdentity.paragraphHash),
                            chunkDurations: chunkDurations)
        return dest
    }
}
