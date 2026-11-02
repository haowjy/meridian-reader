import Foundation

/// The Voice picker's choices that touch files: choosing a voice that isn't on the device, and
/// removing one (decided and run by `SpeechController.removeVoice`; `VoiceDownloads` reads the
/// rows' state).
extension LocalTTSCoordinator {
    /// Settings › Voice's picker, for `VoiceDownloads.pick`.
    static let defaultVoicePicker = "default"

    /// Settings › Voice chose `selection`: it becomes the default for new articles once its files
    /// are on the device (the ✓ moves then), unless a later pick came first. A failed or stopped
    /// download leaves the default as it was.
    func chooseDefault(_ selection: VoiceSelection) async {
        guard await voiceDownloads.pick(selection, for: Self.defaultVoicePicker) else { return }
        setDefaultSelection(selection)
    }

    /// The default new articles take once `selection` is removed: its library's default voice
    /// when that stays on the device, else the built-in one; nil when the default doesn't change.
    func defaultAfterRemoving(_ selection: VoiceSelection, _ removal: VoiceRemoval) -> VoiceSelection? {
        let affected = removal.removesEngine ? defaultSelection.engine == selection.engine : defaultSelection == selection
        guard affected else { return nil }
        if !removal.removesEngine, let voice = engines.descriptor(selection.engine)?.resolvedVoice(nil), voice != selection.voice {
            let fallback = VoiceSelection(engine: selection.engine, voice: voice)
            if case .onDevice = voiceDownloads.status(of: fallback) { return fallback }
        }
        return builtInDefaultSelection
    }

    /// The files step of a voice's removal (`SpeechController.removeVoice`, which decided `removal`
    /// and `newDefault` and stopped listening when it had to). Articles in it keep it: the next
    /// time one plays or prepares, its voice downloads again while playback waits (never another
    /// voice).
    func removeVoice(_ selection: VoiceSelection, _ removal: VoiceRemoval, newDefault: VoiceSelection?) throws {
        defer { voiceDownloads.filesChanged() }
        try engines.remove(selection.voice, for: selection.engine)
        if removal.removesEngine || voice(for: selection.engine) == selection.voice {
            // A host loads its first voice's files: it starts again in the library's default
            // voice, so nothing downloads the removed one unless an article asks for it.
            if let fallback = engines.descriptor(selection.engine)?.resolvedVoice(nil), fallback != selection.voice {
                setEngineVoice(selection.engine, fallback)
            }
            // Its host goes after the call in flight; the next work for it loads a fresh one.
            synthQueue.dropHost(engineID: selection.engine.rawValue)
        }
        if let newDefault { setDefaultSelection(newDefault) }
        noteBakeMarksChanged()
    }
}
