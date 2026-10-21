import SwiftUI
import AVFoundation

/// Settings › Listening, on the Settings card:
///
/// 1. **Voice ›**: the default voice for new articles and books, from the one voice switcher
///    (`VoicePage`, `VoiceSelectionList`: engines are its sections, C138a). No engine control.
/// 3. **Language ›**: Automatic (match article) or a manual language (`LanguagePage`).
/// 4. **Speed ›**: the playback speeds, the list Now Playing's speed opens (`SpeedPage`).
struct ListeningSettingsSection: View {
    @Bindable var speech: SpeechController

    private var localTTS: LocalTTSCoordinator { speech.localTTS }

    var body: some View {
        Section {
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
            if let notice = localTTS.engineCrashNotice {
                Text(notice).foregroundStyle(Palette.destructive).listFooter()
            }
        }
        .listCard()
    }

    // MARK: - Values shown on the rows

    private var voiceName: String { localTTS.voiceName(of: localTTS.defaultSelection) }

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
