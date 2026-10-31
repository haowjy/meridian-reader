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
    /// Settings default, which it keeps.
    @discardableResult
    func selection(for key: UUID) -> VoiceSelection {
        if let stored = storedSelection(of: key) { return stored }
        let locked = VoiceSelection(stored: lockArticleSelection(key, defaultSelection.stored)) ?? defaultSelection
        selectionMemo[key] = .some(locked)
        return locked
    }

    /// The selection `key` speaks in, without locking it (`selection(for:)`): its own, else the
    /// default it would take. A menu's *Voice* row shows it.
    func effectiveSelection(of key: UUID) -> VoiceSelection {
        storedSelection(of: key) ?? defaultSelection
    }

    /// Why the article with `key` and these `paragraphs` can't be read, as ▶'s toast and Prepare say
    /// it: its voice library can't run on this device ("Kokoro needs an iPhone 13 or newer."), or
    /// its language isn't one that library speaks ("Can't read French yet."). nil: it can be read.
    func cantReadNotice(of key: UUID, paragraphs: [String]) -> String? {
        let engine = effectiveSelection(of: key).engine
        if let notice = engines.cantRunNotice(engine) { return notice }
        guard let descriptor = engines.descriptor(engine) else { return nil }
        return ListenLanguage.unspoken(in: paragraphs, by: descriptor).map(ListenLanguage.refusal)
    }

    /// The article can be read here (`cantReadNotice`): its audio renders ahead.
    func rendersAhead(_ key: UUID, paragraphs: [String]) -> Bool {
        cantReadNotice(of: key, paragraphs: paragraphs) == nil
    }

    /// The cache voice key of `selection`'s audio ("kokoro.af_heart"); nil when no registered
    /// engine speaks it.
    func cacheVoice(of selection: VoiceSelection) -> String? {
        engines.descriptor(selection.engine)?.cacheVoiceID(engineVoice: selection.voice)
    }

    /// "kokoro.af_heart" → local.kokoro/af_heart (any revision of the engine's model); nil when no
    /// registered engine wrote it.
    func selection(fromCacheVoice voice: String) -> VoiceSelection? {
        engines.selection(forCacheVoice: voice)
    }

    /// Settings picked a new default. Changes no article that already has a voice; loads its
    /// engine so new articles render.
    func setDefaultSelection(_ selection: VoiceSelection) {
        defaultSelection = selection
        defaults.set(selection.stored, forKey: Self.defaultSelectionKey)
        Task { await loadEngine(selection.engine) }
        synthQueue.renderTargetChanged()
        noteBakeMarksChanged()
    }

    /// The voice a fresh install starts with: the default engine's default voice (Phonon's
    /// Zoey). Settings shows "Default" while it is the pick.
    var builtInDefaultSelection: VoiceSelection { Self.builtInDefault(of: engines) }

    static func builtInDefault(of engines: EngineRegistry) -> VoiceSelection {
        let d = engines.defaultEngine
        return VoiceSelection(engine: d.id, voice: d.defaultVoiceID ?? d.voices.first?.id ?? "")
    }

    /// The stored default, else the built-in one (`builtInDefaultSelection`), which is then
    /// stored. A stored default in an engine no longer registered (a retired engine, Apple's
    /// voices) takes the built-in one too, every launch it is found.
    func loadDefaultSelection() {
        if let stored = defaults.string(forKey: Self.defaultSelectionKey).flatMap(VoiceSelection.init(stored:)),
           engines.contains(stored.engine) {
            defaultSelection = stored
            return
        }
        defaultSelection = builtInDefaultSelection
        defaults.set(defaultSelection.stored, forKey: Self.defaultSelectionKey)
    }

    /// Load the engine an article needs (one is loaded at a time).
    func loadEngineIfNeeded(_ id: SpeechEngineID) {
        guard engines.contains(id), engines.supports(id) else { return }
        switch synth.state {
        case .warming(id, _, _), .ready(id): return
        default: Task { await loadEngine(id) }
        }
    }

    /// Wait until the engine the article with `key` speaks in is loaded; false when it can't be
    /// (unsupported, failed).
    func awaitEngine(for key: UUID) async -> Bool {
        let engine = selection(for: key).engine
        guard engines.contains(engine), engines.supports(engine) else { return false }
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

    /// What the screen calls a voice outside the Voice picker: "Default" while it is the built-in
    /// default, else its voice library's short name ("Kokoro"), as Settings › Voice says it;
    /// never the voice's own name, which means nothing before you have heard it.
    func voiceSummary(of selection: VoiceSelection) -> String {
        selection == builtInDefaultSelection ? String(localized: "Default") : engines.shortName(selection.engine)
    }

    /// The same for a cache voice key (prepared audio, audio from listening); one no registered
    /// engine wrote is named as stored.
    func voiceSummary(ofCacheVoice voiceID: String) -> String {
        engines.selection(forCacheVoice: voiceID).map(voiceSummary(of:)) ?? voiceID
    }
}
