import AVFoundation
import Foundation

/// C138a: one selection (engine + voice) per article and per book, resolved here and passed
/// explicitly to playback, rendering, preparing and cache lookup.
extension LocalTTSCoordinator {
    static let defaultSelectionKey = "reader.voiceSelection.default"

    /// The article's (or its book's) selection; nil: it has none yet (memoized).
    func storedSelection(of key: UUID) -> VoiceSelection? {
        if let memo = selectionMemo[key] { return memo }
        let selection = articleSelection(key).flatMap(VoiceSelection.init(stored:))
        selectionMemo[key] = .some(selection)
        return selection
    }

    /// The selection the article with `key` speaks in from now on: its own, else (brand new) the
    /// Settings default, which it keeps; Apple when the default's engine can't speak the
    /// article's language (`paragraphs`, when known).
    @discardableResult
    func selection(for key: UUID, paragraphs: [String]? = nil) -> VoiceSelection {
        if let stored = storedSelection(of: key) { return stored }
        let first = peekSelection(of: key, paragraphs: paragraphs)
        let locked = VoiceSelection(stored: lockArticleSelection(key, first.stored)) ?? first
        selectionMemo[key] = .some(locked)
        return locked
    }

    /// The selection `key` would speak in, without locking it (`selection(for:paragraphs:)`).
    func peekSelection(of key: UUID, paragraphs: [String]? = nil) -> VoiceSelection {
        if let stored = storedSelection(of: key) { return stored }
        if !defaultSelection.isApple, let paragraphs, !localLanguageAllows(paragraphs) {
            return VoiceSelection(engine: .apple, voice: "")
        }
        return defaultSelection
    }

    /// The article speaks in an on-device voice this device has: its audio renders ahead.
    func rendersAhead(_ key: UUID, paragraphs: [String]) -> Bool {
        let selection = peekSelection(of: key, paragraphs: paragraphs)
        return engines.isOnDevice(selection.engine) && engines.supports(selection.engine)
    }

    /// What a menu's *Voice* row shows: the article's own, else the default it would take.
    func effectiveSelection(of key: UUID) -> VoiceSelection {
        storedSelection(of: key) ?? defaultSelection
    }

    /// The cache voice key of `selection`'s audio ("kokoro.af_heart"); nil for Apple.
    func cacheVoice(of selection: VoiceSelection) -> String? {
        engines.descriptor(selection.engine)?.cacheVoiceID(engineVoice: selection.voice)
    }

    /// "kokoro.af_heart" → local.kokoro/af_heart; nil when no installed engine wrote it.
    func selection(fromCacheVoice voice: String) -> VoiceSelection? {
        for d in engines.localDescriptors {
            guard let prefix = d.onDevice?.cacheVoicePrefix, voice.hasPrefix(prefix + ".") else { continue }
            return VoiceSelection(engine: d.id, voice: String(voice.dropFirst(prefix.count + 1)))
        }
        return nil
    }

    /// Settings picked a new default. Changes no article that already has a voice; loads its
    /// engine so new articles render.
    func setDefaultSelection(_ selection: VoiceSelection) {
        defaultSelection = selection
        defaults.set(selection.stored, forKey: Self.defaultSelectionKey)
        // A pick in Settings is a fresh try of a crashed engine too.
        if engines.isOnDevice(selection.engine) { Task { await loadEngine(selection.engine) } }
        synthQueue.renderTargetChanged()
        noteBakeMarksChanged()
    }

    /// The stored default, else (first launch after C138a) the engine and voices chosen before.
    func loadDefaultSelection(legacyEngine: SpeechEngineID, legacyAppleVoice: String?) {
        if let stored = defaults.string(forKey: Self.defaultSelectionKey).flatMap(VoiceSelection.init(stored:)),
           engines.contains(stored.engine) {
            defaultSelection = stored
            return
        }
        if engines.isOnDevice(legacyEngine), let voice = engineVoices[legacyEngine] {
            defaultSelection = VoiceSelection(engine: legacyEngine, voice: voice)
        } else {
            defaultSelection = VoiceSelection(engine: .apple, voice: legacyAppleVoice ?? "")
        }
        defaults.set(defaultSelection.stored, forKey: Self.defaultSelectionKey)
    }

    /// Load the on-device engine an article needs (one is loaded at a time). An engine that
    /// crashed this session stays off until Retry or a pick in Settings.
    func loadEngineIfNeeded(_ id: SpeechEngineID) {
        guard engines.isOnDevice(id), engines.supports(id), id != crashedEngineID else { return }
        switch synth.state {
        case .warming(id, _, _), .ready(id): return
        default: Task { await loadEngine(id) }
        }
    }

    /// Wait until the engine the article with `key` speaks in is loaded; false when it can't be
    /// (Apple, unsupported, crashed, failed).
    func awaitEngine(for key: UUID) async -> Bool {
        let engine = selection(for: key).engine
        guard engines.isOnDevice(engine) else { return false }
        guard engines.supports(engine), engine != crashedEngineID else { return false }
        await loadEngine(engine)
        return synth.state.readyEngineID == engine
    }

    /// Any library edit: selections are read again when next asked.
    func forgetArticleVoices() { selectionMemo.removeAll() }

    /// A selection was set from a menu: read selections again, and the queue renders in the new one.
    func articleVoicesChanged() {
        selectionMemo.removeAll()
        synthQueue.renderTargetChanged()
        noteBakeMarksChanged()
    }

    /// The short name a *Voice* row shows: "Heart", "Ava (Apple)", "Apple" (the best for the language).
    func voiceName(of selection: VoiceSelection) -> String {
        if selection.isApple {
            guard !selection.voice.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: selection.voice) else {
                return engines.descriptor(.apple)?.shortName ?? "Apple"
            }
            return String(localized: "\(voice.name) (Apple)")
        }
        let d = engines.descriptor(selection.engine)
        return d?.voices.first { $0.id == selection.voice }?.label ?? d?.shortName ?? selection.voice
    }
}
