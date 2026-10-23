import SwiftUI

/// ⋯ › Settings (the last row of every ⋯ panel): every setting in the app, on the Library's list
/// style (cards on paper, `SectionHeader`s), top to bottom:
///
/// ```
/// Settings                                              Done
/// Listening    Voice ›, Language ›, Speed ›
/// Appearance   Appearance › (System / Light / Dark + Color on the pushed page)
/// Reading      Reading › (shared `ReadingAppearancePanel` / Aa controls on the pushed page)
/// Browsing     Block Ads (on)
/// Prepared audio    Prepared audio ›, the audio kept on this iPhone
/// Developer    (developer options only) listen debug, fake extraction failure, the panel
/// Version 1.0 (1)                        (2 s long-press: developer options on / off)
/// ```
///
/// Reading opens the same `ReadingAppearancePanel` as Aa on the Reader and Now Playing, so the two
/// never disagree.
struct SettingsView: View {
    @Bindable var speech: SpeechController
    let onDone: () -> Void

    @Environment(\.readingAppearance) private var reading
    @Environment(ContentBlocker.self) private var contentBlocker
    @Environment(DeveloperSettings.self) private var developer
    /// Confirmation after the version row's long-press toggles developer options.
    @State private var developerToggleNotice: String?

    var body: some View {
        NavigationStack {
            List {
                ListeningSettingsSection(speech: speech)
                appearanceLinkSection
                readingLinkSection
                BrowsingSettingsSection(blocker: contentBlocker)
                StorageSettingsSection(speech: speech)
                if developer.isEnabled {
                    DeveloperSettingsSection()
                }
                versionSection
            }
            .cardListStyle()
            .navigationTitle(Verbs.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetBarButton(Verbs.done, placement: .confirmationAction, identifier: "settingsDone", action: onDone)
            }
            .accessibilityIdentifier("settingsList")
        }
        .alert(developerToggleNotice ?? "", isPresented: Binding(
            get: { developerToggleNotice != nil },
            set: { if !$0 { developerToggleNotice = nil } }
        )) {
            Button(Verbs.ok, role: .cancel) {}
        } message: {
            Text(developer.isEnabled
                 ? "Debug tools are shown in Settings › Developer. Long-press the version again to hide them."
                 : "Debug tools are hidden.")
        }
    }

    // MARK: - Appearance / Reading drill-ins

    private var appearanceLinkSection: some View {
        Section {
            SettingsLinkRow(title: String(localized: "Appearance"), symbol: nil,
                            value: AppAppearance.shared.mode.title,
                            accessibilityID: "settingsAppearance") {
                AppearanceSettingsPage(appearance: AppAppearance.shared)
            }
        }
        .listCard()
    }

    private var readingLinkSection: some View {
        Section {
            SettingsLinkRow(title: String(localized: "Reading"), symbol: nil,
                            value: reading.theme.title,
                            accessibilityID: "settingsReading") {
                ReadingSettingsPage()
            }
        }
        .listCard()
    }

    // MARK: - Version / developer options

    private var versionSection: some View {
        Section {
            SymbolRow(DeveloperSettings.versionLabel, symbol: nil, ink: Palette.secondaryInk) {
                if developer.isEnabled {
                    Text("Developer options")
                        .typeStyle(.caption)
                }
            }
            .onLongPressGesture(minimumDuration: DeveloperSettings.unlockPressSeconds) {
                toggleDeveloperOptions()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settingsVersionRow")
            .accessibilityAction(named: developer.isEnabled
                                 ? "Turn off developer options" : "Turn on developer options") {
                toggleDeveloperOptions()
            }
        }
        .listCard()
    }

    private func toggleDeveloperOptions() {
        developer.isEnabled.toggle()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        developerToggleNotice = developer.isEnabled ? "Developer options on" : "Developer options off"
    }
}

/// Settings › Appearance: the app's appearance and its colour (`AppAppearance`).
private struct AppearanceSettingsPage: View {
    @Bindable var appearance: AppAppearance

    var body: some View {
        List {
            Section {
                SettingsControlRow(title: Verbs.theme) {
                    ChoicePicker(options: AppearanceMode.allCases, selection: $appearance.mode,
                                 identifier: "appearanceMode") { mode in
                        Text(mode.title).typeStyle(.row)
                    }
                }
                SettingsControlRow(title: String(localized: "Color")) {
                    AccentThemePicker(selection: $appearance.accent)
                }
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(String(localized: "Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Reading: the shared Aa panel (`ReadingAppearancePanel` → `TextAppearancePanel`).
private struct ReadingSettingsPage: View {
    @Environment(\.readingAppearance) private var appearance

    var body: some View {
        List {
            Section {
                ReadingAppearancePanel(appearance: appearance)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("How the Reader and Now Playing show articles. Aa at the top of either changes the same settings.")
                    .listFooter()
            }
            .listCard()
        }
        .cardListStyle()
        .navigationTitle(String(localized: "Reading"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settingsReadingPage")
    }
}

/// Settings › Browsing: Block Ads (`ContentBlocker`).
private struct BrowsingSettingsSection: View {
    @Bindable var blocker: ContentBlocker

    var body: some View {
        Section {
            SettingsToggleRow(title: String(localized: "Block Ads"), symbol: Icons.blockAds,
                              isOn: $blocker.isEnabled, accessibilityID: "blockAdsToggle")
        } header: {
            SectionHeader(title: String(localized: "Browsing")).listHeader()
        } footer: {
            Text("Stops common ad and tracker sites from loading in web pages, Follow's included. A change applies to pages loaded after it.")
                .listFooter()
        }
        .listCard()
    }
}

/// Settings › Prepared Audio & Storage (C134): the Prepared Audio list, and the audio kept on
/// this iPhone in two figures: prepared (chosen, never cleared automatically) and from listening
/// (cleared once its article leaves Recent).
private struct StorageSettingsSection: View {
    let speech: SpeechController

    @Environment(PrepareCenter.self) private var preparedAudio
    @State private var preparedBytes: Int64?
    @State private var listeningBytes: Int64?

    var body: some View {
        let overview = preparedAudio.overview
        Section {
            SettingsLinkRow(title: Verbs.preparedAudio, symbol: Icons.preparedAudio,
                            value: overview.isEmpty ? String(localized: "None") : "\(overview.done.count + overview.queued.count + overview.differentVoice.count)",
                            accessibilityID: "settingsPreparedAudio") {
                PreparedAudioList()
            }
            sizeRow(String(localized: "Prepared Audio"), bytes: preparedBytes, id: "settingsPreparedSize")
            sizeRow(String(localized: "Audio From Listening"), bytes: listeningBytes, id: "settingsAudioSize")
        } header: {
            SectionHeader(title: String(localized: "Prepared Audio & Storage")).listHeader()
        } footer: {
            Text("Prepared audio stays until you delete it. Audio from listening is cleared once its article leaves the last \(LibraryStore.recentLimit) in Recent.")
                .listFooter()
        }
        .listCard()
        .task {
            let cache = speech.localTTS.audioCache
            let held = Set(preparedAudio.heldArticleKeys)
            let dirs = cache.cachedArticleKeys().map { (held.contains($0), cache.directory(for: $0)) }
            let (p, l) = await Task.detached(priority: .utility) {
                dirs.reduce((Int64(0), Int64(0))) { sum, d in
                    let bytes = FileSizes.allocatedBytes(at: d.1)
                    return d.0 ? (sum.0 + bytes, sum.1) : (sum.0, sum.1 + bytes)
                }
            }.value
            preparedBytes = p
            listeningBytes = l
        }
    }

    private func sizeRow(_ title: String, bytes: Int64?, id: String) -> some View {
        SymbolRow(title, symbol: Icons.storage) {
            Text(bytes.map(FileSizes.label) ?? "…")
                .typeStyle(.row)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// Settings › Developer (developer options only, at the bottom): the listen debug chip on Now
/// Playing, a fake failure for every extraction, and the listen debug panel.
private struct DeveloperSettingsSection: View {
    @Environment(DeveloperSettings.self) private var developer
    @Environment(ShellState.self) private var shell

    var body: some View {
        @Bindable var developer = developer
        Section {
            SettingsToggleRow(title: Verbs.listenDebug, symbol: Icons.debug,
                              isOn: $developer.listenDebugEnabled, accessibilityID: "listenDebugEnabledToggle")
            SettingsToggleRow(title: String(localized: "Fake Extraction Failure"), symbol: Icons.warning,
                              isOn: $developer.fakeExtractionFailure, accessibilityID: "fakeExtractionFailureToggle")
            Button {
                // Over Settings, which stay when it closes (`ShellState.overSheet`).
                shell.present(.listenDebug)
            } label: {
                SymbolRow(String(localized: "Listen Debug Panel"), symbol: Icons.debug) {
                    Image(systemName: Icons.disclosure)
                        .disclosureSymbol()
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listenDebugSettings")
        } header: {
            SectionHeader(title: String(localized: "Developer")).listHeader()
        } footer: {
            Text("Listen Debug shows a Debug chip on Now Playing for a live render queue overlay; a long-press on ▶ there opens the panel. Fake Extraction Failure makes every extraction fail (Reader, Save, Follow, Prepared Audio) until the app quits.")
                .listFooter()
        }
        .listCard()
    }
}
