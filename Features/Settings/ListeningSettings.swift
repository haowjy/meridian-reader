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
/// one voice switcher. An article or a book that already has audio keeps its own.
struct VoicePage: View {
    @Bindable var speech: SpeechController
    @State private var preview = VoicePreviewPlayer()

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        List {
            VoiceSelectionList(
                speech: speech, current: localTTS.defaultSelection, preparingID: localTTS.voiceDownloadID,
                footer: String(localized: "New articles and books use this voice. To change it for one you’ve already listened to, use Voice in its ⋯ menu."),
                error: localTTS.voiceDownloadError, preview: preview
            ) { selection in
                Task {
                    guard await localTTS.downloadVoice(selection.voice, for: selection.engine) else { return }
                    localTTS.setDefaultSelection(selection)
                }
            }
        }
        .cardListStyle()
        .navigationTitle(Verbs.voice)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { preview.stop() }
    }

    /// A default voice's second line: its detail, then that it is the default ("Default" alone
    /// when it has no detail).
    static func defaultVoiceSubtitle(_ detail: String) -> String {
        detail.isEmpty ? String(localized: "Default") : String(localized: "\(detail) (default)")
    }
}
