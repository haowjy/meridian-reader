import Foundation

/// What removing a voice's download does, decided once (`SpeechController.voiceRemoval(of:)`):
/// the question Settings › Voice asks is made from it, and `removeVoice(_:)` carries it out.
struct VoiceRemovalPlan: Equatable {
    let selection: VoiceSelection
    /// The files: what they free, and whether the library's shared model goes with them.
    let removal: VoiceRemoval
    /// What you're listening to (playing or paused) speaks in it, or in its library when the model
    /// goes: listening stops first, rather than waiting mid-article for the voice to download again.
    let stopsListening: Bool
    /// The default new articles take afterwards; nil when the default doesn't change.
    let newDefault: VoiceSelection?

    /// Nothing depends on it: it goes without a question.
    var asks: Bool { removal.removesEngine || stopsListening || newDefault != nil }
}

/// Removing a voice's download is one operation of the speech layer: the decision says what it
/// changes, and the command revalidates it, stops listening when it must, removes the files and
/// moves what depended on them. Views ask (with the plan's facts) and invoke; they never stop
/// playback or work out who is affected themselves.
extension SpeechController {
    /// What removing `selection` would do now; nil when it can't be removed (not on the device,
    /// downloading, or shipped in the app on its own).
    func voiceRemoval(of selection: VoiceSelection) -> VoiceRemovalPlan? {
        guard let removal = localTTS.voiceDownloads.removal(of: selection) else { return nil }
        let listening = activeSessionID.map { localTTS.effectiveSelection(of: $0) }
        let stops = listening.map { removal.removesEngine ? $0.engine == selection.engine : $0 == selection } ?? false
        return VoiceRemovalPlan(selection: selection, removal: removal, stopsListening: stops,
                                newDefault: localTTS.defaultAfterRemoving(selection, removal))
    }

    /// Carry out `plan` if it still holds. When what it would do has changed since it was asked
    /// (listening started, the default moved, the voice is downloading), nothing is removed and the
    /// fresh plan comes back, to ask again; nil when done, or when there is nothing to remove.
    @discardableResult
    func removeVoice(_ plan: VoiceRemovalPlan) throws -> VoiceRemovalPlan? {
        guard let now = voiceRemoval(of: plan.selection) else { return nil }
        guard now == plan else { return now }
        if now.stopsListening { stop() }
        try localTTS.removeVoice(now.selection, now.removal, newDefault: now.newDefault)
        return nil
    }
}
