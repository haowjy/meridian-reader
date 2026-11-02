import SwiftUI

/// Settings › Listening, on the Settings card:
///
/// 1. **Voice ›**: the default voice for new articles and books, from the one voice switcher
///    (`VoicePage`, `VoiceSelectionList`: compact Engine chips then that engine's voices, C138a).
/// 2. **Speed ›**: the playback speeds, the list Now Playing's speed opens (`SpeedPage`).
struct ListeningSettingsSection: View {
    @Bindable var speech: SpeechController

    @Environment(\.settingsSearch) private var search

    static let group = SettingsSearch.Group(title: String(localized: "Listening"),
                                            rows: [Verbs.voice, Verbs.speed])

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        if search.shows(Self.group) {
            Section {
                if search.shows(Verbs.voice, in: Self.group) {
                    SettingsLinkRow(title: Verbs.voice, value: voiceValue,
                                    accessibilityID: "settingsVoice", route: .voice)
                }
                if search.shows(Verbs.speed, in: Self.group) {
                    SettingsLinkRow(title: Verbs.speed, value: ListenRate.label(speech.rateMultiplier),
                                    accessibilityID: "settingsSpeed", route: .speed)
                }
            } header: {
                SectionHeader(title: Self.group.title, size: .settings).listHeader()
            }
            .listCard()
        }
    }

    // MARK: - Values shown on the rows

    /// "Default" while the built-in voice is the pick, else its voice library ("Kokoro"): never a
    /// voice's name, which means nothing before you have heard it.
    private var voiceValue: String { localTTS.voiceSummary(of: localTTS.defaultSelection) }
}

/// Settings › Listening › Speed: `ListenRate`'s speeds, slowest first, with Now Playing's speed
/// list's labels and ids (`listenSpeedOption-1×`); the chosen one ✓.
struct SpeedPage: View {
    @Bindable var speech: SpeechController

    var body: some View {
        List {
            Section {
                ForEach(ListenRate.options, id: \.self) { rate in
                    SettingsChoiceRow(title: ListenRate.label(rate), subtitle: nil,
                                      selected: speech.rateMultiplier == rate,
                                      accessibilityID: "listenSpeedOption-\(ListenRate.label(rate))") {
                        speech.setRateMultiplier(rate)
                    }
                }
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(Verbs.speed)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Listening › Voice: the default voice for new articles and books (C138a), from the
/// one voice switcher. An article or a book that already has audio keeps its own. Picking a voice
/// that isn't on the device downloads it, and the ✓ moves once it is there
/// (`LocalTTSCoordinator.chooseDefault`). *Edit* (top right) gives each downloaded voice the
/// List's delete control; a swipe offers *Remove* too. Removing the default, or a voice library's
/// last voice (its shared model), asks first.
struct VoicePage: View {
    @Bindable var speech: SpeechController
    @State private var preview = VoicePreviewPlayer()
    @State private var editing = false
    /// The voice whose removal is being asked about.
    @State private var asking: VoiceSelection?

    @Environment(ShellState.self) private var shell
    #if DEBUG
    @Environment(\.voicePageProbe) private var probe
    #endif

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        List {
            VoiceSelectionList(
                speech: speech, current: localTTS.defaultSelection,
                footer: String(localized: "New articles and books use this voice. To change it for one you’ve already listened to, use Voice in its ⋯ menu."),
                preview: preview, onRemove: askRemoval
            ) { selection in
                Task { await localTTS.chooseDefault(selection) }
            }
        }
        .cardListStyle()
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .navigationTitle(Verbs.voice)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? Verbs.done : Verbs.edit) {
                    withAnimation(Motion.snappy) { editing.toggle() }
                }
                .fontWeight(editing ? .semibold : .regular)
                .accessibilityIdentifier("voiceEdit")
            }
        }
        .alert(asking.map(removalTitle) ?? "",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            Button(Verbs.remove, role: .destructive) {
                if let asking { remove(asking) }
                asking = nil
            }
            .accessibilityIdentifier("voiceRemoveConfirm")
            Button(Verbs.cancel, role: .cancel) { asking = nil }
        } message: {
            if let asking { Text(removalMessage(asking)) }
        }
        .onDisappear { preview.stop() }
        #if DEBUG
        .task {
            if probe.editing { editing = true }
            if let voice = probe.removing,
               let engine = localTTS.engines.descriptors.first(where: { $0.allVoices.contains { $0.id == voice } }) {
                try? await Task.sleep(for: .seconds(1))
                askRemoval(VoiceSelection(engine: engine.id, voice: voice))
            }
        }
        #endif
    }

    /// Removes at once a voice nothing depends on; asks first about the default, the voice of what
    /// you're listening to, and a library's last voice (its shared model goes too).
    private func askRemoval(_ selection: VoiceSelection) {
        guard let removal = localTTS.voiceDownloads.removal(of: selection) else { return }
        if removal.removesEngine || localTTS.defaultAfterRemoving(selection, removal) != nil
            || stopsListening(selection, removal) {
            asking = selection
        } else {
            remove(selection)
        }
    }

    /// What you're listening to (playing or paused) speaks in `selection`, or in its library when
    /// the removal takes the library's model: removing it stops listening first, rather than
    /// leaving playback to wait for the voice to download again mid-article.
    private func stopsListening(_ selection: VoiceSelection, _ removal: VoiceRemoval) -> Bool {
        guard let key = speech.activeSessionID else { return false }
        let listening = localTTS.effectiveSelection(of: key)
        return removal.removesEngine ? listening.engine == selection.engine : listening == selection
    }

    private func remove(_ selection: VoiceSelection) {
        if let removal = localTTS.voiceDownloads.removal(of: selection), stopsListening(selection, removal) {
            speech.stop()
        }
        shell.attempt(String(localized: "Couldn’t remove \(name(of: selection))")) {
            try localTTS.removeVoice(selection)
        }
    }

    private func name(of selection: VoiceSelection) -> String {
        localTTS.engines.descriptor(selection.engine)?.allVoices.first { $0.id == selection.voice }?.label
            ?? selection.voice
    }

    /// "Remove Kokoro?" for a library's last voice, else "Remove Bella?".
    private func removalTitle(_ selection: VoiceSelection) -> String {
        let removal = localTTS.voiceDownloads.removal(of: selection)
        let subject = removal?.removesEngine == true ? localTTS.engines.shortName(selection.engine) : name(of: selection)
        return String(localized: "Remove \(subject)?")
    }

    /// What it frees, then what changes: "Frees 164 MB. Kokoro voices will need to download again.
    /// What you’re listening to is in Kokoro, so listening stops. New articles will use Zoey.
    /// Articles already in Kokoro download it again before they play."
    private func removalMessage(_ selection: VoiceSelection) -> String {
        guard let removal = localTTS.voiceDownloads.removal(of: selection) else { return "" }
        var parts: [String] = []
        let subject: String
        if removal.removesEngine {
            subject = localTTS.engines.shortName(selection.engine)
            parts.append(String(localized: "Frees \(FileSizes.megabytes(removal.bytes)). \(subject) voices will need to download again."))
        } else {
            subject = name(of: selection)
            parts.append(String(localized: "Frees \(FileSizes.megabytes(removal.bytes))."))
        }
        if stopsListening(selection, removal) {
            parts.append(String(localized: "What you’re listening to is in \(subject), so listening stops."))
        }
        if let next = localTTS.defaultAfterRemoving(selection, removal) {
            parts.append(String(localized: "New articles will use \(name(of: next))."))
            parts.append(String(localized: "Articles already in \(subject) download it again before they play."))
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
/// A Debug launch's look at the Voice page (`LaunchTestHooks`): Edit on, or a voice's *Remove*.
struct VoicePageProbe: Equatable {
    var editing = false
    /// The engine voice id whose *Remove* runs a second in ("af_heart").
    var removing: String?
}

extension EnvironmentValues {
    @Entry var voicePageProbe = VoicePageProbe()
}
#endif
