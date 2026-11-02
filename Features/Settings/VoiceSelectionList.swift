import SwiftUI

/// C138a: the one voice switcher. A compact Voices control (Phonon | Kokoro) filters the list;
/// that voice library's voices follow (with samples and downloads, `VoiceChoiceRows`), or why it can't run on
/// this device. Picking a voice picks its engine. Settings › Voice (the default for new articles) and an article's or a book's *Voice*
/// picker (`VoicePickerSheet`) are this list.
///
/// ```
/// Voices   [ Phonon | Kokoro ]
/// KOKORO
/// ( ▶ )  Heart                 ✓
/// ( ▶ )  Bella                 ◔■
///        164 MB
/// ( ▶ )  Emma                  ⤓
///        164 MB
/// ```
struct VoiceSelectionList: View {
    @Bindable var speech: SpeechController
    /// The selection with the checkmark.
    let current: VoiceSelection?
    var footer: String
    /// Why the last pick didn't change anything (a save that failed), under the list.
    var error: String?
    let preview: VoicePreviewPlayer
    /// Removes a downloaded voice (Settings › Voice); nil: this picker removes nothing.
    var onRemove: ((VoiceSelection) -> Void)?
    let onPick: (VoiceSelection) -> Void

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    /// Engine whose voices are listed. nil until the user taps one: the current selection's engine.
    @State private var shownEngine: SpeechEngineID?

    private var engines: [EngineDescriptor] {
        localTTS.engines.descriptors.filter { !$0.voices.isEmpty }
    }

    private var visibleEngine: SpeechEngineID {
        shownEngine ?? current?.engine ?? localTTS.engines.defaultEngine.id
    }

    /// Engine first (Phonon / Kokoro), then only that engine's voices.
    var body: some View {
        engineSelector
        if let descriptor = engines.first(where: { $0.id == visibleEngine }) {
            engineSection(descriptor)
            if !descriptor.moreVoices.isEmpty, localTTS.engines.supports(descriptor.id) {
                moreVoicesSection(descriptor)
            }
        }
    }

    /// Compact Phonon | Kokoro chips (same ChoicePicker as Appearance), not tall choice rows.
    private var engineOptions: [SpeechEngineID] { engines.map(\.id) }

    private var engineSelection: Binding<SpeechEngineID> {
        Binding(get: { visibleEngine }, set: { shownEngine = $0 })
    }

    @ViewBuilder
    private var engineSelector: some View {
        Section {
            SettingsControlRow(title: String(localized: "Voices")) {
                ChoicePicker(options: engineOptions, selection: engineSelection,
                             identifier: "engineRow") { id in
                    Text(engineChipLabel(id)).typeStyle(.row)
                }
            }
        }
        .listCard()
    }

    private func engineChipLabel(_ id: SpeechEngineID) -> String {
        localTTS.engines.shortName(id)
    }

    /// Same engine, listing only its *More voices* (VoiceChoiceRows lists `descriptor.voices`).
    private static func moreDescriptor(_ d: EngineDescriptor) -> EngineDescriptor {
        var more = d
        more.voices = d.moreVoices
        return more
    }

    @ViewBuilder
    private func moreVoicesSection(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let more = Self.moreDescriptor(descriptor)
        Section {
            VoiceChoiceRows(descriptor: more, current: current?.engine == id ? current?.voice : nil,
                            preview: preview, speech: speech, onRemove: onRemove) { voice in
                onPick(VoiceSelection(engine: id, voice: voice.id))
            }
        } header: {
            SectionHeader(title: String(localized: "More voices")).listHeader()
        }
        .listCard()
    }

    @ViewBuilder
    private func engineSection(_ descriptor: EngineDescriptor) -> some View {
        let id = descriptor.id
        let supported = localTTS.engines.supports(id)
        Section {
            if supported {
                VoiceChoiceRows(descriptor: descriptor, current: current?.engine == id ? current?.voice : nil,
                                preview: preview, speech: speech, onRemove: onRemove) { voice in
                    onPick(VoiceSelection(engine: id, voice: voice.id))
                }
            } else {
                Text(localTTS.engines.blockReason(id) ?? String(localized: "Not supported on this device"))
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            SectionHeader(title: descriptor.displayName).listHeader()
        } footer: {
            if case .failed(id, let message) = localTTS.synth.state(of: id) {
                Text(message).foregroundStyle(Palette.destructive).listFooter()
            } else {
                footerText.listFooter()
            }
        }
        .listCard()
    }

    /// What the picked voice is for (`footer`), or why the last pick changed nothing.
    @ViewBuilder
    private var footerText: some View {
        if let error {
            Text(error).foregroundStyle(Palette.destructive)
        } else {
            Text(footer)
        }
    }
}
