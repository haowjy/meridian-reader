import SwiftUI
import AVFoundation

/// Settings › Listening, on the Settings card:
///
/// 1. **Voice ›**: the default voice for new articles and books, from the one voice switcher
///    (`VoicePage`, `VoiceSelectionList`: compact Engine chips then that engine's voices, C138a).
/// 3. **Language ›**: Automatic (match article) or a manual language (`LanguagePage`).
/// 4. **Speed ›**: the playback speeds, the list Now Playing's speed opens (`SpeedPage`).
struct ListeningSettingsSection: View {
    @Bindable var speech: SpeechController

    @Environment(\.settingsSearch) private var search

    static let group = SettingsSearch.Group(title: String(localized: "Listening"),
                                            rows: [Verbs.voice, Verbs.language, Verbs.speed])

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        if search.shows(Self.group) {
            Section {
                if search.shows(Verbs.voice, in: Self.group) {
                    SettingsLinkRow(title: Verbs.voice, value: voiceValue,
                                    accessibilityID: "settingsVoice", route: .voice)
                }
                if search.shows(Verbs.language, in: Self.group) {
                    SettingsLinkRow(title: Verbs.language, value: languageName,
                                    accessibilityID: "settingsLanguage", route: .language)
                }
                if search.shows(Verbs.speed, in: Self.group) {
                    SettingsLinkRow(title: Verbs.speed, value: ListenRate.label(speech.rateMultiplier),
                                    accessibilityID: "settingsSpeed", route: .speed)
                }
            } header: {
                SectionHeader(title: Self.group.title, size: .settings).listHeader()
            } footer: {
                if let notice = localTTS.engineCrashNotice {
                    Text(notice).foregroundStyle(Palette.destructive).listFooter()
                }
            }
            .listCard()
        }
    }

    // MARK: - Values shown on the rows

    /// "Default" while the built-in voice is the pick, else its voice library ("Kokoro", "Apple"):
    /// never a voice's name, which means nothing before you have heard it.
    private var voiceValue: String {
        let selection = localTTS.defaultSelection
        return selection == localTTS.builtInDefaultSelection ? String(localized: "Default")
            : localTTS.engines.shortName(selection.engine)
    }

    private var languageName: String {
        speech.languageAutomatic ? String(localized: "Automatic")
            : VoiceCatalog.languageName(for: speech.selectedLanguageCode)
    }
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
                footer: String(localized: "New articles and books speak in this voice. One already with audio keeps its own: change it from its More menu › Voice."),
                error: localTTS.voiceDownloadError, preview: preview
            ) { selection in
                Task {
                    if !selection.isApple {
                        guard await localTTS.downloadVoice(selection.voice, for: selection.engine) else { return }
                    }
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
                        Text("Automatic detects each article's language. A new article in a language the default voice can't speak takes Apple's voice for that language.")
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
