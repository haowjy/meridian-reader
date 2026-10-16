import SwiftUI
import AVFoundation

/// Settings › Listening, on the Settings card:
///
/// 1. **Engine**: Apple + on-device engines from `EngineRegistry` (download %, cancel, ready,
///    swipe-to-delete, crash notice). Fixed two-line rows: state changes only swap the subtitle
///    text and the fixed-size trailing accessory, so rows never change height.
/// 2. **Voice ›**: the selected engine's voices (`VoicePage`).
/// 3. **Language ›**: Automatic (match article) or a manual language (`LanguagePage`).
/// 4. **Speed**: the playback speeds in one line.
struct ListeningSettingsSection: View {
    @Bindable var speech: SpeechController

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        Section {
            if let system = localTTS.engines.systemDescriptor {
                SettingsChoiceRow(
                    title: system.displayName,
                    subtitle: system.subtitle,
                    selected: localTTS.selectedEngineID == system.id,
                    accessibilityID: "engineRow-\(system.id.rawValue)"
                ) {
                    Task { await localTTS.selectEngine(system.id) }
                }
            }
            ForEach(localTTS.engines.localDescriptors) { descriptor in
                localEngineRow(descriptor)
            }
            SettingsLinkRow(title: String(localized: "Voice"), symbol: Icons.voice, value: voiceName,
                            accessibilityID: "settingsVoice") {
                VoicePage(speech: speech)
            }
            SettingsLinkRow(title: String(localized: "Language"), symbol: Icons.browser, value: languageName,
                            accessibilityID: "settingsLanguage") {
                LanguagePage(speech: speech)
            }
            SettingsControlRow(title: String(localized: "Speed")) {
                ChoicePicker(options: ListenRate.options.map(RateOption.init), selection: Binding(
                    get: { RateOption(speech.rateMultiplier) },
                    set: { speech.setRateMultiplier($0.rate) }
                ), identifier: "settingsSpeed") { option in
                    // Six to a line: the caption size keeps "1.75×" whole, every label the same size.
                    Text(ListenRate.label(option.rate))
                        .typeStyle(.caption, weight: .semibold)
                        .monospacedDigit()
                }
            }
        } header: {
            SettingsSectionHeader(title: String(localized: "Listening"))
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let notice = localTTS.engineCrashNotice {
                    Text(notice).foregroundStyle(Palette.destructive)
                } else if case .failed(_, let message) = localTTS.synth.state {
                    Text(message).foregroundStyle(Palette.destructive)
                }
                Text("On-device voices download once, then work offline. Swipe left on a downloaded engine to delete it.")
            }
            .settingsFooter()
        }
        .settingsCard()
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
                // Download ring doubles as the Cancel button (no extra rows appear).
                Button {
                    localTTS.synth.cancelDownload()
                } label: {
                    DownloadRing(fraction: localTTS.synth.state.warmingProgress)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel \(descriptor.shortName) download")
                .accessibilityIdentifier("engineCancel-\(id.rawValue)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if gateOK, localTTS.isModelInstalled(id), !pending {
                // The row stays (to download again), so not `.destructive` (`Palette.destructive`).
                Button("Delete") {
                    try? localTTS.deleteModel(id)
                }
                .tint(Palette.destructive)
            }
        }
    }

    private func localSubtitle(_ descriptor: EngineDescriptor, gateOK: Bool) -> String {
        let id = descriptor.id
        if !gateOK {
            return localTTS.engines.blockReason(id) ?? "Not supported on this device"
        }
        if localTTS.synth.state.warmingEngineID == id {
            if let fraction = localTTS.synth.state.warmingProgress, fraction < 1 {
                return "Downloading… \(Int(fraction * 100))%"
            }
            return "Preparing…"
        }
        if localTTS.engineCrashNotice != nil, localTTS.selectedEngineID != id {
            return "Crashed last session – tap to try again"
        }
        if localTTS.synth.state.readyEngineID == id {
            return descriptor.isRecommended ? "Ready (recommended)" : "Ready"
        }
        if localTTS.isModelInstalled(id) {
            return "Downloaded – tap to use"
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

/// A speed as a choice (`ChoicePicker` needs identifiable options).
private struct RateOption: Identifiable, Hashable {
    let rate: Double
    var id: String { ListenRate.label(rate) }

    init(_ rate: Double) {
        // The stored rate matched to the nearest option, so the picker always shows one.
        self.rate = ListenRate.options.min { abs($0 - rate) < abs($1 - rate) } ?? rate
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
        .libraryListStyle()
        .navigationTitle(String(localized: "Voice"))
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
                    subtitle: voice.id == descriptor.defaultVoiceID ? Self.defaultVoiceSubtitle(voice.detail) : voice.detail,
                    selected: current == voice.id && localTTS.voiceDownloadID == nil,
                    busy: downloading,
                    accessibilityID: "voiceRow-\(voice.id)"
                ) {
                    Task { await localTTS.chooseVoice(voice.id, for: descriptor.id) }
                } accessory: {
                    if VoicePreviewPlayer.hasPreview(voice) {
                        Button {
                            if speech.isPlaying { speech.pause() }
                            preview.toggle(voice)
                        } label: {
                            Image(systemName: preview.playingID == voice.id ? Icons.previewStop : Icons.previewPlay)
                                .font(.title3)
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preview.playingID == voice.id ? "Stop preview" : "Preview \(voice.label)")
                        .accessibilityIdentifier("voicePreview-\(voice.id)")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(title: descriptor.displayName)
        } footer: {
            Group {
                if let error = localTTS.voiceDownloadError {
                    Text(error).foregroundStyle(Palette.destructive)
                } else {
                    Text("Switching voice re-renders listened articles in the new voice; the old voice keeps playing until each paragraph is ready.")
                }
            }
            .settingsFooter()
        }
        .settingsCard()
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
                subtitle: VoiceCatalog.languageName(for: speech.effectiveLanguageCode),
                selected: appleSelectedID == nil,
                accessibilityID: "voiceRow-system"
            ) {
                speech.selectVoice(identifier: nil)
            }
            ForEach(VoiceCatalog.voices(forLanguage: speech.effectiveLanguageCode)) { entry in
                SettingsChoiceRow(
                    title: entry.voice.name,
                    subtitle: "\(entry.qualityLabel), \(entry.languageDisplayName)",
                    selected: appleSelectedID == entry.id,
                    accessibilityID: "voiceRow-\(entry.id)"
                ) {
                    speech.selectVoice(identifier: entry.id)
                }
            }
        } header: {
            SettingsSectionHeader(title: localTTS.engines.systemDescriptor?.displayName ?? "")
        } footer: {
            Text("Enhanced and Premium voices can be added in iOS Settings → Accessibility → Spoken Content → Voices.")
                .settingsFooter()
        }
        .settingsCard()
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
                    subtitle: automaticSubtitle,
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
                .settingsFooter()
            }
            .settingsCard()
        }
        .libraryListStyle()
        .navigationTitle(String(localized: "Language"))
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

/// A Settings section's title, as the Library's lists draw theirs.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        SectionHeader(title: title)
            .libraryHeader()
    }
}
