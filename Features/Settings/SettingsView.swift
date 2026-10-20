import SwiftUI

/// ⋯ › Settings (the last row of every ⋯ panel): every setting in the app, on the Library's list
/// style (cards on paper, `SectionHeader`s), top to bottom:
///
/// ```
/// Settings                                              Done
/// Appearance   [ System | Light | Dark ]  Color (●)(●)(●)(●)(●)
/// Reading      themes (◐)(Aa)(Aa)(Aa)(Aa), font, size [A] 100% [A], spacing, Scroll / Pages, a sample
/// Listening    engines (download, ↓ once downloaded, ✓ chosen), Voice ›, Language ›, Speed [0.75× … 2×]
/// Browsing     Block Ads (on)
/// Downloads    Downloads ›, the audio kept on this iPhone
/// Developer    (developer options only) listen debug, fake extraction failure, the panel
/// Version 1.0 (1)                        (2 s long-press: developer options on / off)
/// ```
///
/// Reading edits the same store as the Aa panel on the Reader and Now Playing
/// (`ReadingAppearance`), so the two never disagree.
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
                AppearanceSettingsSection(appearance: AppAppearance.shared)
                ReadingSettingsSection(appearance: reading)
                ListeningSettingsSection(speech: speech)
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
private struct AppearanceSettingsSection: View {
    @Bindable var appearance: AppAppearance

    var body: some View {
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
        } header: {
            SectionHeader(title: String(localized: "Appearance")).listHeader()
        }
        .listCard()
    }
}

/// Settings › Reading: the reading theme, typeface, text size, line spacing and Scroll or Pages, the
/// same store and controls as the Aa panel, with a sample in what is chosen.
private struct ReadingSettingsSection: View {
    @Bindable var appearance: ReadingAppearance

    var body: some View {
        let accent = AppAppearance.shared.accent
        Section {
            SettingsControlRow(title: Verbs.theme) {
                ReadingThemePicker(selection: $appearance.theme, accent: accent)
            }
            SettingsControlRow(title: String(localized: "Font")) {
                ChoicePicker(options: ReadingFont.allCases, selection: $appearance.font, identifier: "readingFont") { font in
                    Text(font.title).typeStyle(.row, weight: .medium, design: font.design)
                }
            }
            SettingsControlRow(title: Verbs.textSize) {
                TextSizeStepper(model: appearance.textSizeModel)
            }
            SettingsControlRow(title: String(localized: "Line Spacing")) {
                ChoicePicker(options: ReadingLineSpacing.allCases, selection: $appearance.lineSpacing,
                             identifier: "readingLineSpacing") { spacing in
                    Text(spacing.title).typeStyle(.row)
                }
            }
            SettingsControlRow(title: String(localized: "Layout")) {
                ChoicePicker(options: ReadingLayout.allCases, selection: $appearance.layout,
                             identifier: "readingLayout") { layout in
                    Text(layout.title).typeStyle(.row)
                }
            }
            ReadingSample(palette: appearance.palette(accent: accent), font: appearance.font,
                          textScale: appearance.textScale, lineSpacing: appearance.lineSpacing)
                .padding(.vertical, Spacing.xs)
        } header: {
            SectionHeader(title: String(localized: "Reading")).listHeader()
        } footer: {
            Text("How the Reader and Now Playing show pages. Aa at the top of either changes the same settings.")
                .listFooter()
        }
        .listCard()
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

/// Settings › Downloads & Storage: the Downloads list, and how much listening audio is kept.
private struct StorageSettingsSection: View {
    let speech: SpeechController

    @Environment(DownloadCenter.self) private var downloads
    @State private var audioBytes: Int64?

    var body: some View {
        let overview = downloads.overview
        Section {
            SettingsLinkRow(title: Verbs.downloads, symbol: Icons.downloads,
                            value: overview.isEmpty ? String(localized: "None") : "\(overview.done.count + overview.queued.count + overview.differentVoice.count)",
                            accessibilityID: "settingsDownloads") {
                DownloadsList()
            }
            SymbolRow(String(localized: "Listening Audio"), symbol: Icons.storage) {
                Text(audioBytes.map(FileSizes.label) ?? "…")
                    .typeStyle(.row)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settingsAudioSize")
        } header: {
            SectionHeader(title: String(localized: "Downloads & Storage")).listHeader()
        } footer: {
            Text("Listening audio is kept on this iPhone for pages you saved or downloaded; audio for pages you only opened is cleared after a while.")
                .listFooter()
        }
        .listCard()
        .task {
            let root = speech.localTTS.audioCache.root
            audioBytes = await Task.detached(priority: .utility) { FileSizes.allocatedBytes(at: root) }.value
        }
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
            Text("Listen Debug shows a Debug chip on Now Playing for a live render queue overlay; a long-press on ▶ there opens the panel. Fake Extraction Failure makes every extraction fail (Reader, Save, Follow, Downloads) until the app quits.")
                .listFooter()
        }
        .listCard()
    }
}
