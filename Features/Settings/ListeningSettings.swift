import SwiftUI
import AVFoundation

/// Settings › Listening, on the Settings card:
///
/// 1. **Engine**: Apple + on-device engines from `EngineRegistry` (download %, cancel, ready,
///    swipe-to-delete, crash notice). Fixed two-line rows: state changes only swap the subtitle
///    text and the fixed-size trailing accessory, so rows never change height.
/// 2. **Voice ›**: the selected engine's voices (`VoicePage`).
/// 3. **Language ›**: Automatic (match article) or a manual language (`LanguagePage`).
/// 4. **Speed ›**: the playback speeds, the list Now Playing's speed opens (`SpeedPage`).
struct ListeningSettingsSection: View {
    @Bindable var speech: SpeechController

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        Section {
            if let system = localTTS.engines.systemDescriptor {
                SettingsChoiceRow(
                    title: system.displayName,
                    subtitle: DetailPart(system.subtitle),
                    selected: localTTS.selectedEngineID == system.id,
                    accessibilityID: "engineRow-\(system.id.rawValue)"
                ) {
                    Task { await localTTS.selectEngine(system.id) }
                }
            }
            ForEach(localTTS.engines.localDescriptors) { descriptor in
                localEngineRow(descriptor)
            }
            // No symbols in this card: the engines above are choices without one (a card's rows
            // all lead with a symbol, or none does).
            SettingsLinkRow(title: Verbs.voice, symbol: nil, value: voiceName,
                            accessibilityID: "settingsVoice") {
                VoicePage(speech: speech)
            }
            SettingsLinkRow(title: Verbs.language, symbol: nil, value: languageName,
                            accessibilityID: "settingsLanguage") {
                LanguagePage(speech: speech)
            }
            SettingsLinkRow(title: Verbs.speed, symbol: nil, value: ListenRate.label(speech.rateMultiplier),
                            accessibilityID: "settingsSpeed") {
                SpeedPage(speech: speech)
            }
        } header: {
            SectionHeader(title: String(localized: "Listening")).listHeader()
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let notice = localTTS.engineCrashNotice {
                    Text(notice).foregroundStyle(Palette.destructive)
                } else if case .failed(_, let message) = localTTS.synth.state {
                    Text(message).foregroundStyle(Palette.destructive)
                }
                Text("On-device voices download once, then work offline. Swipe left on a downloaded engine to remove its download.")
                if !VoiceCatalog.hasHighQualityVoice(forLanguage: speech.effectiveLanguageCode) {
                    // C129: Siri's voices aren't offered to apps; better Apple voices are a download.
                    Text("Better Apple voices (Enhanced or Premium) can be downloaded in iOS Settings > Accessibility > Spoken Content > Voices.")
                        .accessibilityIdentifier("appleVoiceHint")
                }
            }
            .listFooter()
        }
        .listCard()
    }

    // MARK: - Engine

    @ViewBuilder
    private func localEngineRow(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let gateOK = localTTS.engines.supports(id)
        let pending = localTTS.synth.state.warmingEngineID == id

        SettingsChoiceRow(
            title: descriptor.displayName,
            subtitle: localSubtitle(descriptor, gateOK: gateOK),
            selected: localTTS.synth.state.readyEngineID == id,
            enabled: gateOK,
            accessibilityID: "engineRow-\(id.rawValue)"
        ) {
            guard gateOK, !pending else { return }
            Task { await localTTS.selectEngine(id) }
        } accessory: {
            if pending {
                // The download's mark doubles as the Cancel button (no extra rows appear).
                Button {
                    localTTS.synth.cancelDownload()
                } label: {
                    ModelDownloadMark(fraction: localTTS.synth.state.warmingProgress)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel \(descriptor.shortName) download")
                .accessibilityIdentifier("engineCancel-\(id.rawValue)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if gateOK, localTTS.isModelInstalled(id), !pending {
                // What was downloaded goes: *Remove Download*, as for a page's or a folder's. The
                // row stays (to download again), so not `.destructive` (`Palette.destructive`).
                MenuRow(id: "engineRemoveDownload", title: Verbs.removeDownload, icon: Icons.removeDownload,
                        isDestructive: true) { try? localTTS.deleteModel(id) }
                    .swipeButton()
            }
        }
    }

    /// Line two: the model's state, after the accent filled ↓ once it is downloaded (as a downloaded row's
    /// line two starts), so the trailing slots hold only its download's progress and the
    /// selection ✓.
    private func localSubtitle(_ descriptor: EngineDescriptor, gateOK: Bool) -> DetailPart {
        let text = localState(descriptor, gateOK: gateOK)
        let downloaded = gateOK && localTTS.isModelInstalled(descriptor.id)
            && localTTS.synth.state.warmingEngineID != descriptor.id
        return downloaded ? .downloaded(text) : DetailPart(text)
    }

    private func localState(_ descriptor: EngineDescriptor, gateOK: Bool) -> String {
        let id = descriptor.id
        if !gateOK {
            return localTTS.engines.blockReason(id) ?? String(localized: "Not supported on this device")
        }
        if localTTS.synth.state.warmingEngineID == id {
            if let fraction = localTTS.synth.state.warmingProgress, fraction < 1 {
                return String(localized: "Downloading… \(Int(fraction * 100))%")
            }
            return String(localized: "Preparing…")
        }
        if localTTS.engineCrashNotice != nil, localTTS.selectedEngineID != id {
            return String(localized: "Crashed last session. Tap to try again.")
        }
        if localTTS.synth.state.readyEngineID == id {
            return descriptor.isRecommended ? String(localized: "Ready (recommended)") : String(localized: "Ready")
        }
        if localTTS.isModelInstalled(id) {
            return String(localized: "Downloaded. Tap to use.")
        }
        return descriptor.subtitle
    }

    // MARK: - Values shown on the rows

    private var voiceName: String {
        if let descriptor = localTTS.engines.descriptor(localTTS.selectedEngineID), descriptor.onDevice != nil,
           !descriptor.voices.isEmpty {
            let current = descriptor.resolvedVoice(localTTS.voice(for: descriptor.id))
            return descriptor.voices.first { $0.id == current }?.label ?? ""
        }
        if let id = speech.selectedVoiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice.name
        }
        return String(localized: "System default")
    }

    private var languageName: String {
        speech.languageAutomatic ? String(localized: "Automatic")
            : VoiceCatalog.languageName(for: speech.selectedLanguageCode)
    }
}

/// Settings › Listening › Speed: `ListenRate`'s speeds, slowest first, with Now Playing's speed
/// list's labels and ids (`listenSpeedOption-1×`); the chosen one ✓.
private struct SpeedPage: View {
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

/// Settings › Listening › Voice: the selected engine's voices (descriptor `voices`: Kokoro's
/// curated list with bundled previews) or, for Apple, the system voices for the effective
/// language.
struct VoicePage: View {
    @Bindable var speech: SpeechController
    @State private var preview = VoicePreviewPlayer()

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        List {
            if let descriptor = localTTS.engines.descriptor(localTTS.selectedEngineID), descriptor.onDevice != nil,
               !descriptor.voices.isEmpty {
                localVoices(descriptor)
            } else {
                appleVoices
            }
        }
        .cardListStyle()
        .navigationTitle(Verbs.voice)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { preview.stop() }
    }

    @ViewBuilder
    private func localVoices(_ descriptor: EngineDescriptor) -> some View {
        let current = descriptor.resolvedVoice(localTTS.voice(for: descriptor.id))
        Section {
            ForEach(descriptor.voices) { voice in
                let downloading = localTTS.voiceDownloadID == voice.id
                SettingsChoiceRow(
                    title: voice.label,
                    subtitle: DetailPart(voice.id == descriptor.defaultVoiceID ? Self.defaultVoiceSubtitle(voice.detail) : voice.detail),
                    selected: current == voice.id && localTTS.voiceDownloadID == nil,
                    accessibilityID: "voiceRow-\(voice.id)"
                ) {
                    Task { await localTTS.chooseVoice(voice.id, for: descriptor.id) }
                } accessory: {
                    if downloading {
                        // A voice downloading shows as every download does (its size is unknown, so
                        // the mark's spinner), in the slot the preview leaves while it downloads.
                        ModelDownloadMark(fraction: nil)
                            .accessibilityLabel("Downloading \(voice.label)")
                    } else if VoicePreviewPlayer.hasPreview(voice) {
                        Button {
                            if speech.isPlaying { speech.pause() }
                            preview.toggle(voice)
                        } label: {
                            Image(systemName: preview.playingID == voice.id ? Icons.previewStop : Icons.previewPlay)
                                .tileSymbol()
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preview.playingID == voice.id ? "Stop preview" : "Preview \(voice.label)")
                        .accessibilityIdentifier("voicePreview-\(voice.id)")
                    }
                }
            }
        } header: {
            SectionHeader(title: descriptor.displayName).listHeader()
        } footer: {
            Group {
                if let error = localTTS.voiceDownloadError {
                    Text(error).foregroundStyle(Palette.destructive)
                } else {
                    Text("Switching voice re-renders listened articles in the new voice; the old voice keeps playing until each paragraph is ready.")
                }
            }
            .listFooter()
        }
        .listCard()
    }

    /// The Apple voice actually used for the effective language (checkmark).
    private var appleSelectedID: String? {
        guard let id = speech.selectedVoiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: id),
              ListenLanguage.baseCode(voice.language) == ListenLanguage.baseCode(speech.effectiveLanguageCode)
        else { return nil }
        return id
    }

    @ViewBuilder
    private var appleVoices: some View {
        Section {
            SettingsChoiceRow(
                title: String(localized: "System default"),
                subtitle: DetailPart(VoiceCatalog.languageName(for: speech.effectiveLanguageCode)),
                selected: appleSelectedID == nil,
                accessibilityID: "voiceRow-system"
            ) {
                speech.selectVoice(identifier: nil)
            }
            ForEach(VoiceCatalog.voices(forLanguage: speech.effectiveLanguageCode)) { entry in
                SettingsChoiceRow(
                    title: entry.voice.name,
                    subtitle: DetailPart("\(entry.qualityLabel), \(entry.languageDisplayName)"),
                    selected: appleSelectedID == entry.id,
                    accessibilityID: "voiceRow-\(entry.id)"
                ) {
                    speech.selectVoice(identifier: entry.id)
                }
            }
        } header: {
            SectionHeader(title: localTTS.engines.systemDescriptor?.displayName ?? "").listHeader()
        } footer: {
            Text("Enhanced and Premium voices can be added in iOS Settings → Accessibility → Spoken Content → Voices.")
                .listFooter()
        }
        .listCard()
    }

    /// A default voice's second line: its detail, then that it is the default ("Default" alone
    /// when it has no detail).
    static func defaultVoiceSubtitle(_ detail: String) -> String {
        detail.isEmpty ? String(localized: "Default") : String(localized: "\(detail) (default)")
    }
}

/// Settings › Listening › Language: Automatic (match article, `NLLanguageRecognizer`) or a manual
/// language.
struct LanguagePage: View {
    @Bindable var speech: SpeechController

    var body: some View {
        List {
            Section {
                SettingsChoiceRow(
                    title: String(localized: "Automatic (match article)"),
                    subtitle: DetailPart(automaticSubtitle),
                    selected: speech.languageAutomatic,
                    accessibilityID: "languageRow-automatic"
                ) {
                    speech.selectAutomaticLanguage()
                }
                ForEach(VoiceCatalog.availableLanguages()) { language in
                    SettingsChoiceRow(
                        title: language.displayName,
                        subtitle: nil,
                        selected: !speech.languageAutomatic && isSelected(language.code),
                        accessibilityID: "languageRow-\(language.code)"
                    ) {
                        speech.selectLanguage(language.code)
                    }
                }
            } footer: {
                Group {
                    if let note = speech.languageResolution.note {
                        Text("This article: \(note).")
                    } else {
                        Text("Automatic detects each article's language. Articles in a language the selected engine can't speak use Apple's voice for that language.")
                    }
                }
                .listFooter()
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(Verbs.language)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var automaticSubtitle: String {
        if let detected = speech.sessionDetectedLanguage {
            return "This article: \(ListenLanguage.displayName(for: detected))"
        }
        return "Detects each article's language"
    }

    private func isSelected(_ code: String) -> Bool {
        VoiceCatalog.canonicalLang(speech.selectedLanguageCode) == VoiceCatalog.canonicalLang(code)
    }
}
