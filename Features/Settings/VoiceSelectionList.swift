import AVFoundation
import SwiftUI

/// C138a: the one voice switcher. Engines are its sections: each on-device engine's voices (with
/// samples, `VoiceChoiceRows`), then Apple's installed voices for the language, best first
/// (Premium, Enhanced, then the rest). Picking a voice picks its engine; there is no other engine
/// control. Settings › Voice (the default for new articles) and an article's or a book's
/// *Voice* picker (`VoicePickerSheet`) are this list.
///
/// ```
/// KOKORO (ON-DEVICE)
///  Heart  ✓  (default)             ▶   ← swipe Remove Download when another pack is in
///  Bella  ↓ Bright, American       ▶   ← swipe Remove Download when its pack is downloaded
///  Downloading… 40%
/// APPLE
///  Best for English (US)
///  Ava  Premium, English (US)
/// ```
struct VoiceSelectionList: View {
    @Bindable var speech: SpeechController
    /// The selection with the checkmark.
    let current: VoiceSelection?
    /// The voice whose files are downloading.
    var preparingID: String?
    var footer: String
    var error: String?
    let preview: VoicePreviewPlayer
    let onPick: (VoiceSelection) -> Void

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        ForEach(localTTS.engines.localDescriptors.filter { !$0.voices.isEmpty }) { descriptor in
            engineSection(descriptor)
        }
        appleSection
    }

    @ViewBuilder
    private func engineSection(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let supported = localTTS.engines.supports(id)
        Section {
            if supported {
                VoiceChoiceRows(descriptor: descriptor, current: current?.engine == id ? current?.voice : nil,
                                preparingID: preparingID, preview: preview, speech: speech) { voice in
                    onPick(VoiceSelection(engine: id, voice: voice.id))
                }
                modelRow(descriptor)
            } else {
                Text(localTTS.engines.blockReason(id) ?? String(localized: "Not supported on this device"))
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            SectionHeader(title: descriptor.displayName).listHeader()
        } footer: {
            if let notice = localTTS.engineCrashNotice, localTTS.crashedEngineID == nil || localTTS.crashedEngineID == id {
                Text(notice).foregroundStyle(Palette.destructive).listFooter()
            } else if case .failed(id, let message) = localTTS.synth.state {
                Text(message).foregroundStyle(Palette.destructive).listFooter()
            }
        }
        .listCard()
    }

    /// Shared model download progress (ONNX ~175 MB). Per-voice pack removal is a swipe on that
    /// voice row (`VoiceChoiceRows`), not a global Remove Download.
    @ViewBuilder
    private func modelRow(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        if localTTS.synth.state.warmingEngineID == id {
            SettingsChoiceRow(title: modelState, subtitle: nil, selected: false,
                              accessibilityID: "engineCancel-\(id.rawValue)") {
                localTTS.synth.cancelDownload()
            } accessory: {
                ModelDownloadMark(fraction: localTTS.synth.state.warmingProgress)
            }
        }
    }

    private var modelState: String {
        if let fraction = localTTS.synth.state.warmingProgress, fraction < 1 {
            return String(localized: "Downloading… \(Int(fraction * 100))%")
        }
        return String(localized: "Preparing…")
    }

    private var language: String { speech.effectiveLanguageCode }

    /// Apple's installed voices for the language, Premium, then Enhanced, then the rest.
    private var appleEntries: [VoiceCatalog.Entry] {
        VoiceCatalog.voices(forLanguage: language)
            .enumerated()
            .sorted { ($0.element.voice.quality.rawValue, -$0.offset) > ($1.element.voice.quality.rawValue, -$1.offset) }
            .map(\.element)
    }

    @ViewBuilder
    private var appleSection: some View {
        let isApple = current?.isApple == true
        Section {
            SettingsChoiceRow(
                title: String(localized: "Best for \(VoiceCatalog.languageName(for: language))"),
                subtitle: DetailPart(String(localized: "The best installed voice")),
                selected: isApple && current?.voice.isEmpty == true,
                accessibilityID: "voiceRow-system"
            ) {
                onPick(VoiceSelection(engine: .apple, voice: ""))
            }
            ForEach(appleEntries) { entry in
                SettingsChoiceRow(
                    title: entry.voice.name,
                    subtitle: DetailPart("\(entry.qualityLabel), \(entry.languageDisplayName)"),
                    selected: isApple && current?.voice == entry.id,
                    accessibilityID: "voiceRow-\(entry.id)"
                ) {
                    onPick(VoiceSelection(engine: .apple, voice: entry.id))
                }
            }
        } header: {
            SectionHeader(title: localTTS.engines.systemDescriptor?.displayName ?? "Apple").listHeader()
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let error {
                    Text(error).foregroundStyle(Palette.destructive)
                } else {
                    Text(footer)
                }
                if !VoiceCatalog.hasHighQualityVoice(forLanguage: language) {
                    Text("Better Apple voices (Enhanced or Premium) can be downloaded in iOS Settings > Accessibility > Spoken Content > Voices.")
                        .accessibilityIdentifier("appleVoiceHint")
                }
            }
            .listFooter()
        }
        .listCard()
    }
}
