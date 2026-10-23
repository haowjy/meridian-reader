import Foundation

/// The one owner of chunk plans: the `TextChunker` cut of a paragraph's text into synth chunks for
/// an engine, sized by that engine's `OnDeviceTraits.limits`. The render queue, the listen
/// player, the audio cache's alignment and the "still needs audio" rule all read plans here, so a
/// paragraph has one plan per engine wherever it is asked. A plan depends only on the engine and
/// the text, so a voice change keeps them. The paragraphs asked about last are kept, up to about
/// `capacity` (a few books' chapters); older ones are cut again when asked.
@MainActor
final class ChunkPlans {
    static let capacity = 2048

    private struct Key: Hashable {
        var engineID: String
        var text: String
    }

    /// Limits of a registered engine by its cache engine key (nil: none registered).
    private let limits: (String) -> TextChunker.Limits?
    /// Two generations: a hit in `older` moves to `recent`; when `recent` is full it becomes
    /// `older` and the previous `older` is dropped.
    private var recent: [Key: [String]] = [:]
    private var older: [Key: [String]] = [:]

    init(limits: @escaping (String) -> TextChunker.Limits?) {
        self.limits = limits
    }

    /// Synth chunks of `text` for engine `engineID` (a cache engine key), in render order; empty
    /// when the text has nothing to speak. nil for an engine nobody registered.
    func chunks(for text: String, engineID: String) -> [String]? {
        let key = Key(engineID: engineID, text: text)
        if let plan = recent[key] { return plan }
        let plan: [String]
        if let kept = older.removeValue(forKey: key) {
            plan = kept
        } else {
            guard let limits = limits(engineID) else { return nil }
            plan = TextChunker.chunks(for: text, limits: limits)
        }
        if recent.count >= Self.capacity {
            older = recent
            recent = [:]
        }
        recent[key] = plan
        return plan
    }
}
