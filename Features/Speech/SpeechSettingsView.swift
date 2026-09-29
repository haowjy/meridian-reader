import SwiftUI
import AVFoundation

/// Settings → Listen.
///
/// 1. **Engine**: Apple + on-device engines from `EngineRegistry` (download %, cancel, ready,
///    swipe-to-delete, crash notice). Fixed two-line rows: state changes only swap the subtitle
///    text and the fixed-size trailing accessory, so rows never change height.
/// 2. **Voice**: the selected engine's voices (descriptor `voices`: Kokoro's curated list with
///    bundled previews) or, for Apple, the system voices for the effective language.
/// 3. **Language**: Automatic (match article, `NLLanguageRecognizer`) or a manual language.
/// 4. Speed, 5. Debug (developer options only), 6. Version (2 s long-press toggles developer
///    options — `DeveloperOptions`).
struct SpeechSettingsView: View {
    @Bindable var speech: SpeechController
    @State private var preview = VoicePreviewPlayer()
    /// Confirmation after the version row's long-press toggles developer options.
    @State private var developerToggleNotice: String?

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        List {
            engineSection
            voiceSection
            languageSection
            speedSection
            if speech.developerOptionsEnabled {
                debugSection
            }
            aboutSection
        }
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .alert(developerToggleNotice ?? "", isPresented: Binding(
            get: { developerToggleNotice != nil },
            set: { if !$0 { developerToggleNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(speech.developerOptionsEnabled
                 ? "Debug tools are shown in the ⋯ menu and in Voice settings. Long-press the version again to hide them."
                 : "Debug tools are hidden.")
        }
        .onDisappear { preview.stop() }
    }

    // MARK: - Engine

    /// Engine the Voice section follows: the one being prepared, else the selected one.
    private var voiceEngineID: SpeechEngineID {
        localTTS.pendingEngineID ?? localTTS.selectedEngineID
    }

    @ViewBuilder
    private var engineSection: some View {
        Section {
            if let system = localTTS.engines.systemDescriptor {
                SettingsRow(
                    title: system.displayName,
                    subtitle: system.subtitle,
                    selected: localTTS.selectedEngineID == system.id && localTTS.pendingEngineID == nil,
                    accessibilityID: "engineRow-\(system.id.rawValue)"
                ) {
                    Task {
                        await localTTS.selectEngine(system.id)
                        speech.applyEngineSelectionChange()
                    }
                } accessory: {
                    EmptyView()
                }
            }
            ForEach(localTTS.engines.localDescriptors) { descriptor in
                localEngineRow(descriptor)
            }
        } header: {
            Text("Engine")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let notice = localTTS.engineCrashNotice {
                    Text(notice).foregroundStyle(.orange)
                } else if case .failed(let message) = localTTS.downloader.state {
                    Text(message).foregroundStyle(.red)
                }
                Text("On-device voices download once, then work offline. Swipe left on a downloaded engine to delete it.")
            }
        }
    }

    @ViewBuilder
    private func localEngineRow(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let gateOK = localTTS.engines.supports(id)
        let pending = localTTS.pendingEngineID == id
        let selected = pending || (localTTS.selectedEngineID == id && localTTS.pendingEngineID == nil)

        SettingsRow(
            title: descriptor.displayName,
            subtitle: localSubtitle(descriptor, gateOK: gateOK),
            selected: selected && !pending,
            enabled: gateOK,
            accessibilityID: "engineRow-\(id.rawValue)"
        ) {
            guard gateOK, !pending else { return }
            Task {
                await localTTS.selectEngine(id)
                speech.applyEngineSelectionChange()
            }
        } accessory: {
            if pending {
                // Download ring doubles as the Cancel button (no extra rows appear).
                Button {
                    localTTS.cancelDownload()
                } label: {
                    DownloadRing(fraction: localTTS.modelDownloadFraction)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel \(descriptor.shortName) download")
                .accessibilityIdentifier("engineCancel-\(id.rawValue)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if gateOK, localTTS.isModelInstalled(id), !pending {
                Button("Delete", role: .destructive) {
                    try? localTTS.deleteModel(id)
                    speech.applyEngineSelectionChange()
                }
            }
        }
    }

    private func localSubtitle(_ descriptor: EngineDescriptor, gateOK: Bool) -> String {
        let id = descriptor.id
        if !gateOK {
            return localTTS.engines.blockReason(id) ?? "Not supported on this device"
        }
        if localTTS.pendingEngineID == id {
            if let fraction = localTTS.modelDownloadFraction, fraction < 1 {
                return "Downloading… \(Int(fraction * 100))%"
            }
            return "Preparing…"
        }
        if localTTS.engineCrashNotice != nil, localTTS.selectedEngineID != id {
            return "Crashed last session · tap to try again"
        }
        if localTTS.selectedEngineID == id, localTTS.localHostReady {
            return descriptor.isRecommended ? "Ready · recommended" : "Ready"
        }
        if localTTS.isModelInstalled(id) {
            return "Downloaded · tap to use"
        }
        return descriptor.subtitle
    }

    // MARK: - Voice

    @ViewBuilder
    private var voiceSection: some View {
        if let descriptor = localTTS.engines.descriptor(voiceEngineID), descriptor.kind == .onDevice,
           !descriptor.voices.isEmpty {
            localVoiceSection(descriptor)
        } else {
            appleVoiceSection
        }
    }

    @ViewBuilder
    private func localVoiceSection(_ descriptor: EngineDescriptor) -> some View {
        let current = descriptor.resolvedVoice(localTTS.voice(for: descriptor.id))
        Section {
            ForEach(descriptor.voices) { voice in
                let downloading = localTTS.voiceDownloadID == voice.id
                SettingsRow(
                    title: voice.label,
                    subtitle: voice.id == descriptor.defaultVoiceID ? "\(voice.detail) · default" : voice.detail,
                    selected: current == voice.id && localTTS.voiceDownloadID == nil,
                    busy: downloading,
                    accessibilityID: "voiceRow-\(voice.id)"
                ) {
                    Task {
                        if await localTTS.chooseVoice(voice.id, for: descriptor.id) {
                            speech.applyEngineSelectionChange()
                        }
                    }
                } accessory: {
                    if VoicePreviewPlayer.hasPreview(voice) {
                        Button {
                            if speech.isPlaying { speech.pause() }
                            preview.toggle(voice)
                        } label: {
                            Image(systemName: preview.playingID == voice.id ? "stop.circle.fill" : "play.circle")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preview.playingID == voice.id ? "Stop preview" : "Preview \(voice.label)")
                        .accessibilityIdentifier("voicePreview-\(voice.id)")
                    }
                }
            }
        } header: {
            Text("Voice · \(descriptor.shortName)")
        } footer: {
            if let error = localTTS.voiceDownloadError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Switching voice re-renders listened articles in the new voice; the old voice keeps playing until each paragraph is ready.")
            }
        }
    }

    private var appleVoices: [VoiceCatalog.Entry] {
        VoiceCatalog.voices(forLanguage: speech.effectiveLanguageCode)
    }

    /// Apple voice that's actually used for the effective language (checkmark).
    private var appleSelectedID: String? {
        guard let id = speech.selectedVoiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: id),
              ListenLanguage.baseCode(voice.language) == ListenLanguage.baseCode(speech.effectiveLanguageCode)
        else { return nil }
        return id
    }

    @ViewBuilder
    private var appleVoiceSection: some View {
        Section {
            SettingsRow(
                title: "System default",
                subtitle: VoiceCatalog.languageName(for: speech.effectiveLanguageCode),
                selected: appleSelectedID == nil,
                accessibilityID: "voiceRow-system"
            ) {
                speech.selectVoice(identifier: nil)
            } accessory: {
                EmptyView()
            }
            ForEach(appleVoices) { entry in
                SettingsRow(
                    title: entry.voice.name,
                    subtitle: "\(entry.qualityLabel) · \(entry.languageDisplayName)",
                    selected: appleSelectedID == entry.id,
                    accessibilityID: "voiceRow-\(entry.id)"
                ) {
                    speech.selectVoice(identifier: entry.id)
                } accessory: {
                    EmptyView()
                }
            }
        } header: {
            Text("Voice · Apple")
        } footer: {
            Text("Enhanced and Premium voices can be added in iOS Settings → Accessibility → Spoken Content → Voices.")
        }
    }

    // MARK: - Language

    private var languages: [VoiceCatalog.LanguageOption] {
        VoiceCatalog.availableLanguages()
    }

    @ViewBuilder
    private var languageSection: some View {
        Section {
            SettingsRow(
                title: "Automatic (match article)",
                subtitle: automaticSubtitle,
                selected: speech.languageAutomatic,
                accessibilityID: "languageRow-automatic"
            ) {
                speech.selectAutomaticLanguage()
            } accessory: {
                EmptyView()
            }
            ForEach(languages) { language in
                SettingsRow(
                    title: language.displayName,
                    subtitle: nil,
                    selected: !speech.languageAutomatic && isSelectedLanguage(language.code),
                    accessibilityID: "languageRow-\(language.code)"
                ) {
                    speech.selectLanguage(language.code)
                } accessory: {
                    EmptyView()
                }
            }
        } header: {
            Text("Language")
        } footer: {
            if let note = speech.languageResolution.note {
                Text("This article: \(note).")
            } else {
                Text("Automatic detects each article's language. Articles in a language the selected engine can't speak use Apple's voice for that language.")
            }
        }
    }

    private var automaticSubtitle: String {
        if let detected = speech.sessionDetectedLanguage {
            return "This article: \(ListenLanguage.displayName(for: detected))"
        }
        return "Detects each article's language"
    }

    private func isSelectedLanguage(_ code: String) -> Bool {
        VoiceCatalog.canonicalLang(speech.selectedLanguageCode) == VoiceCatalog.canonicalLang(code)
    }

    // MARK: - Speed

    @ViewBuilder
    private var speedSection: some View {
        Section {
            ForEach(SpeechController.rateOptions, id: \.self) { option in
                Button {
                    speech.setRateMultiplier(option)
                } label: {
                    HStack {
                        Text(abs(option - 1.0) < 0.01 ? "1×" : String(format: "%g×", option))
                            .foregroundStyle(.primary)
                        Spacer()
                        if abs(speech.rateMultiplier - option) < 0.01 {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        } header: {
            Text("Speed")
        }
    }

    // MARK: - Version / developer options

    private var aboutSection: some View {
        Section {
            HStack {
                Text(DeveloperOptions.versionLabel)
                Spacer()
                if speech.developerOptionsEnabled {
                    Text("Developer options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: DeveloperOptions.unlockPressSeconds) {
                toggleDeveloperOptions()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settingsVersionRow")
            .accessibilityAction(named: speech.developerOptionsEnabled
                                 ? "Turn off developer options" : "Turn on developer options") {
                toggleDeveloperOptions()
            }
        }
    }

    private func toggleDeveloperOptions() {
        speech.developerOptionsEnabled.toggle()
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        developerToggleNotice = speech.developerOptionsEnabled ? "Developer options on" : "Developer options off"
    }

    // MARK: - Debug

    @ViewBuilder
    private var debugSection: some View {
        Section {
            Toggle(isOn: $speech.listenDebugEnabled) {
                Label("Listen debug", systemImage: "waveform.badge.magnifyingglass")
            }
            .accessibilityIdentifier("listenDebugEnabledToggle")
            if speech.listenDebugEnabled {
                Button {
                    speech.showListenDebug = true
                } label: {
                    Text("Open full panel")
                }
                .accessibilityIdentifier("listenDebugSettings")
            }
        } footer: {
            Text("When on, a Debug chip appears on the listen bar for a live bake/queue overlay. Long-press play/pause still opens the full panel.")
        }
        .sheet(isPresented: $speech.showListenDebug) {
            ListenDebugPanel(speech: speech)
        }
    }
}

/// One fixed-layout settings row: title, optional one-line subtitle, a fixed-size trailing
/// accessory slot, and a fixed-size checkmark slot (checkmark / spinner / empty). State changes
/// swap contents inside the slots, so the row's size never changes.
private struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    var enabled: Bool = true
    var busy: Bool = false
    let accessibilityID: String
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: String?,
        selected: Bool,
        enabled: Bool = true,
        busy: Bool = false,
        accessibilityID: String,
        action: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.enabled = enabled
        self.busy = busy
        self.accessibilityID = accessibilityID
        self.action = action
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(enabled ? .primary : .secondary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(selected ? .isSelected : [])

            accessory()
                .frame(width: 30, height: 30)

            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
    }
}

/// Determinate download ring with a stop square (tap = cancel); indeterminate spinner when the
/// fraction is unknown (preparing / compiling).
private struct DownloadRing: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            if let fraction, fraction < 1 {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}
